//
//  FlowRelay.swift
//  DVPNCore
//

#if os(macOS)
import Network
import NetworkExtension
import os

// MARK: - FlowRelays

/// The relays alive in the extension, so a stop cancels them.
/// `@unchecked`: the dictionary is only touched under the lock.
final class FlowRelays: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[ObjectIdentifier: any FlowRelay]>(initialState: [:])

    func relay(_ flow: NEAppProxyFlow, via interface: NWInterface, on queue: DispatchQueue) {
        let relay: any FlowRelay
        if let tcp = flow as? NEAppProxyTCPFlow {
            relay = TCPRelay(flow: tcp, interface: interface, queue: queue)
        } else if let udp = flow as? NEAppProxyUDPFlow {
            relay = UDPRelay(flow: udp, interface: interface, queue: queue)
        } else {
            flow.closeReadWithError(nil)
            flow.closeWriteWithError(nil)
            return
        }
        let id = ObjectIdentifier(relay)
        lock.withLock { $0[id] = relay }
        relay.start { [weak self] in
            self?.lock.withLock { _ = $0.removeValue(forKey: id) }
        }
    }

    func cancelAll() {
        let all = lock.withLock { relays -> [any FlowRelay] in
            defer { relays.removeAll() }
            return Array(relays.values)
        }
        all.forEach { $0.cancel() }
    }
}

// MARK: - FlowRelay

protocol FlowRelay: AnyObject, Sendable {
    /// Opens the flow and copies until either side ends; `onEnd` runs once, when the relay is over.
    func start(onEnd: @escaping @Sendable () -> Void)
    func cancel()
}

// MARK: - TCPRelay

/// One TCP flow copied both ways between the app and a connection bound to the physical interface, with each
/// side's end of stream passed on to the other.
/// `@unchecked`: the flags are under the lock; the flow and the connection only hear from their own callbacks.
final class TCPRelay: FlowRelay, @unchecked Sendable {
    private struct State {
        var appFinished = false
        var remoteFinished = false
        var ended = false
        var onEnd: (@Sendable () -> Void)?
    }

    private let flow: NEAppProxyTCPFlow
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(flow: NEAppProxyTCPFlow, interface: NWInterface, queue: DispatchQueue) {
        self.flow = flow
        self.queue = queue
        let parameters = NWParameters.tcp
        parameters.requiredInterface = interface
        flow.setMetadata(on: parameters)
        connection = NWConnection(to: flow.remoteFlowEndpoint, using: parameters)
    }

    func start(onEnd: @escaping @Sendable () -> Void) {
        state.withLock { $0.onEnd = onEnd }
        connection.stateUpdateHandler = { [self] connectionState in
            switch connectionState {
            case .ready:
                open()
            case let .failed(error):
                end(error)
            case let .waiting(error):
                // No route on the required interface: fail the flow rather than hold it.
                end(error)
            case .cancelled:
                end(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        end(nil)
    }

    private func open() {
        flow.open(withLocalFlowEndpoint: nil) { [self] error in
            if let error {
                end(error)
                return
            }
            copyToRemote()
            copyToApp()
        }
    }

    private func copyToRemote() {
        flow.readData { [self] data, error in
            if let error {
                end(error)
                return
            }
            guard let data, !data.isEmpty else {
                // The app is done writing: pass its end on and keep copying what the remote still sends.
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
                if finished(.app) { end(nil) }
                return
            }
            connection.send(content: data, completion: .contentProcessed { [self] error in
                if let error {
                    end(error)
                } else {
                    copyToRemote()
                }
            })
        }
    }

    private func copyToApp() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let error {
                end(error)
                return
            }
            if let data, !data.isEmpty {
                flow.write(data) { [self] error in
                    if let error {
                        end(error)
                    } else if isComplete {
                        remoteDone()
                    } else {
                        copyToApp()
                    }
                }
            } else if isComplete {
                remoteDone()
            } else {
                copyToApp()
            }
        }
    }

    private func remoteDone() {
        flow.closeWriteWithError(nil)
        if finished(.remote) { end(nil) }
    }

    private enum Side { case app, remote }

    /// Marks one side finished; true once both are.
    private func finished(_ side: Side) -> Bool {
        state.withLock { state in
            switch side {
            case .app: state.appFinished = true
            case .remote: state.remoteFinished = true
            }
            return state.appFinished && state.remoteFinished
        }
    }

    private func end(_ error: (any Error)?) {
        let onEnd = state.withLock { state -> (@Sendable () -> Void)? in
            guard !state.ended else { return nil }
            state.ended = true
            return state.onEnd
        }
        guard let onEnd else { return }
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        connection.cancel()
        onEnd()
    }
}

// MARK: - UDPRelay

/// One UDP flow: the app's datagrams go out through one connection per remote endpoint, bound to the physical
/// interface, and the answers come back marked with the endpoint they came from.
/// `@unchecked`: the connections are under the lock; the flow only hears from its own callbacks.
final class UDPRelay: FlowRelay, @unchecked Sendable {
    private struct State {
        var connections: [NWEndpoint: NWConnection] = [:]
        var ended = false
        var onEnd: (@Sendable () -> Void)?
    }

    private let flow: NEAppProxyUDPFlow
    private let parameters: NWParameters
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(flow: NEAppProxyUDPFlow, interface: NWInterface, queue: DispatchQueue) {
        self.flow = flow
        self.queue = queue
        parameters = NWParameters.udp
        parameters.requiredInterface = interface
        flow.setMetadata(on: parameters)
    }

    func start(onEnd: @escaping @Sendable () -> Void) {
        state.withLock { $0.onEnd = onEnd }
        flow.open(withLocalFlowEndpoint: nil) { [self] error in
            if let error {
                end(error)
            } else {
                copyToRemote()
            }
        }
    }

    func cancel() {
        end(nil)
    }

    private func copyToRemote() {
        flow.readDatagrams { [self] datagrams, error in
            if let error {
                end(error)
                return
            }
            guard let datagrams, !datagrams.isEmpty else {
                end(nil)   // the app closed its socket
                return
            }
            for (datagram, endpoint) in datagrams {
                connection(to: endpoint).send(content: datagram, completion: .idempotent)
            }
            copyToRemote()
        }
    }

    private func connection(to endpoint: NWEndpoint) -> NWConnection {
        if let existing = state.withLock({ $0.connections[endpoint] }) { return existing }
        let connection = NWConnection(to: endpoint, using: parameters)
        state.withLock { $0.connections[endpoint] = connection }
        connection.stateUpdateHandler = { [self] connectionState in
            switch connectionState {
            case .failed, .cancelled:
                drop(endpoint)
            case .waiting:
                drop(endpoint)
            default:
                break
            }
        }
        connection.start(queue: queue)
        copyToApp(from: connection, at: endpoint)
        return connection
    }

    private func copyToApp(from connection: NWConnection, at endpoint: NWEndpoint) {
        connection.receiveMessage { [self] data, _, _, error in
            if error != nil {
                drop(endpoint)
                return
            }
            if let data, !data.isEmpty {
                flow.writeDatagrams([(data, endpoint)]) { [self] error in
                    if let error { end(error) }
                }
            }
            copyToApp(from: connection, at: endpoint)
        }
    }

    private func drop(_ endpoint: NWEndpoint) {
        state.withLock { $0.connections.removeValue(forKey: endpoint) }?.cancel()
    }

    private func end(_ error: (any Error)?) {
        let (connections, onEnd) = state.withLock { state -> ([NWConnection], (@Sendable () -> Void)?) in
            guard !state.ended else { return ([], nil) }
            state.ended = true
            defer { state.connections.removeAll() }
            return (Array(state.connections.values), state.onEnd)
        }
        guard let onEnd else { return }
        connections.forEach { $0.cancel() }
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        onEnd()
    }
}
#endif
