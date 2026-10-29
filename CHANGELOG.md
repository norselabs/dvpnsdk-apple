# Changelog

Changes that apps can notice, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The
versions follow [Semantic Versioning](https://semver.org); until 1.0.0 a minor version may change the API.

## Unreleased

### Changed

- The app no longer links the WireGuard engine and its Go runtime, which started at every launch: `DVPNTunnel` and
  `DVPNWireGuardCore` take WireGuardKit's configuration types from the new target `WireGuardKitTypes`, which links no
  engine. `WireGuardKit` re-exports it, so an extension that imports `WireGuardKit` changes nothing; an app that
  imported `WireGuardKit` through `DVPNTunnel` imports `WireGuardKitTypes` instead.

## 0.4.0 (2026-10-28)

The `HevSocks5Tunnel` engine is new, hev-socks5-tunnel 2.19.3 (see *Fixed*); the other engines are those of 0.1.0.
The API changed: see *Changed*.

### Added

- `Server.address`: the node's address on the network (`sentnode…`), when the backend sends one.
- `RequestPayload.queryAndJSON`: a request's query items and a JSON body together.

### Changed

- `ConnectionCredentials` reads the WireGuard key, for WireGuard and AmneziaWG nodes, from the credentials answer's
  `connection_handshake.request.private_key`, and the top-level `private_key` only when the request has none. The
  top-level field is an older copy that the backend will stop sending. Up to 0.3.0 the SDK read only that field, so
  an app on 0.3.0 or older cannot start a WireGuard or AmneziaWG tunnel once it is gone (`emptyCredentials`): update
  to this version before then.
- `ConnectionAPIClient`'s `quickCredentials`, `countryCredentials` and `cityCredentials` take a list of node types, as
  `serverCredentials` does, instead of one or none, and send it as the lists do: in the `filter` query, comma-joined in
  the order given, with an empty JSON body. An empty list sends none, as `nil` did, and the backend then picks only
  WireGuard or V2Ray nodes. To update, pass `[nodeType]` for a node type and `[]` for `nil`.
- A disconnect or a server switch no longer waits for the provider to write its `ExtensionLogFile`, which takes about
  ten seconds on an iPhone. A provider now writes the file only after a failure: when its start fails, when its tunnel
  stops for a reason nobody asked for (a lost network, for instance), and when `TunnelManager` stops a start that
  timed out or never completed a WireGuard handshake. So a log exported after an ordinary disconnect holds no provider
  lines from that connection. A subclass of `ProxyPacketTunnelProvider` or `WireGuardPacketTunnelProvider` that
  overrides `handleAppMessage(_:)` passes the messages it does not handle to `super`.
- The split-tunnel proxy's warning about a flow with no physical interface no longer names the app; a private debug
  line, which the log file never holds, does.
- The API client logs under the host app's bundle identifier, like the tunnel layer, instead of `com.dvpnsdk`, so a
  log an app reads by its subsystem has the requests too.
- `MirroredTransport` logs one line per request at the notice level, which the system keeps: the method, the path,
  the status and the backend's error code or the failure, and the time it took. In this line and the transport's
  others, a path segment that is not a word (an ID an app put in the path) shows as "…".
- A fallback to a mirror is logged at the notice level instead of info.
- `SplitTunnelManager` says that its calls must not overlap or be cancelled: a call pauses inside, so a newer one made
  in that pause can be overtaken by it, and a cancelled one can start a proxy that is still stopping.
- A log line prints an error by the SDK's own words, or by the system's words with the error's domain and code, never
  whole: no line prints a file error's full path or a Swift error's values. `TunnelActivationError` and
  `SplitTunnelError` add a system error's domain and code to their description.
- `AmneziaWGParameterError` shows an invalid `HeaderProtectionKey` by its length.
- Values the SDK owns (a profile's name, timeouts, the tunnel interface) are logged public, so these lines no longer
  read `<private>`.
- A path segment of up to three characters shows in the log only when it is letters.
- Xray's own log is off; it wrote to standard output, which an extension discards.
- The split-tunnel proxy says whether apps are selected, not how many.

### Fixed

- A TCP connection through the Xray, V2Ray or Hysteria 2 tunnel ends about a second after the far side closes it,
  instead of a minute later. The `HevSocks5Tunnel` engine is now hev-socks5-tunnel 2.19.3 instead of 2.8.0, which
  passed such a close on to the app only when its 60-second `read-write-timeout` ran out, so an app that read until
  the server closed waited that minute. A connection on which nothing comes back for 60 seconds is still closed then,
  as before: so is one to a destination the node cannot reach, which the proxy accepts before the node dials.
- A request whose primary endpoint never answers goes on to a mirror again, within its timeout. Since 0.2.0 the
  request's deadline, as long as the primary's own timeout, cancelled the primary first, so no mirror was tried. Now a
  primary that has neither begun its answer nor taken the request's body within
  `BackendConfiguration.mirrorRequestTimeout` has a mirror looked up; once one is ready, a GET goes to the mirror too
  and the first answer wins, and a request with a body moves to the mirror. A request without a body that is not a GET
  stays with the primary, which may already be acting on it, and so does a request whose timeout is no longer than
  `mirrorRequestTimeout`.
- A preferred mirror that never answers gives the request back to the primary, within its timeout. Once
  `refreshEndpoint` found the primary down, or a mirror answered for it, requests went to a mirror and left it only
  when no mirror could be found at all, so a silent mirror, or a search for one that outlasted the request, failed
  every request until the next refresh, whether the primary answered or not. Now a mirror that has not started on the
  request within `mirrorRequestTimeout` hands it to the primary by the same rules the other way round, and the
  primary's success brings later requests back to it. A refresh that finds no mirror leaves requests with the primary.
- `SplitTunnelManager` reads its proxy configuration from the system at every call, so one removed in System
  Settings while the app runs is made again at the next call (macOS may ask to allow it again) instead of
  being started, which never connects. It still keeps the configuration it loaded last, so the system goes on
  posting its proxy's status changes.
- `TunnelManager.connectedNode()` returns the node on iOS and tvOS too: the tunnel providers recorded it on macOS only.
- A proxy engine's start reason, which the provider records for the app, and Xray's start error keep the SDK error's
  own words (its `description`) instead of "The operation couldn't be completed", which they read since the errors
  stopped being `LocalizedError`s.
- `WireGuardAdapter.start` builds without the "'weak' ownership of capture 'self'" warning that recent Swift
  compilers give in every app that builds the package.

### Security

- Xray's and Hysteria's start errors, which the provider logs and records for the app, show every credential the
  extension holds as "…" (Xray quotes a malformed VLESS or VMess ID whole).

## 0.3.0 (2026-10-13)

The engines are those of 0.1.0. The API changed: see *Changed* and *Removed*.

### Added

- `ExtensionLogFile`: each tunnel provider writes the lines the system kept of its own process to a file in the App
  Group when its tunnel stops or its start fails (`ExtensionLogFile.directory`, `urls()`), so an app can add the
  extensions' lines to a log it exports. Arguments logged as private stay `<private>`.

### Changed

- The errors (`TunnelsServiceError`, `TunnelActivationError`, `SplitTunnelError`, `XraySourceError`, `HysteriaError`,
  `XConfigurationError`, `AmneziaWGParameterError`, `TLSLeafProbe.Error`) are no longer `LocalizedError`s: the SDK writes no user text. Each describes itself for the log
  (`CustomStringConvertible`), and `TunnelsServiceError` and `TunnelActivationError` compare by case, a system error
  counting by its domain and code.
- `SplitTunnelSettings.Mode` is `CaseIterable`.
- Only the package sees what only it uses: `XraySourceStore.removeIfUnreadable()`, `HysteriaConfigurationStore`,
  `TunnelConfigDirectories.homeDirectory` and `SplitTunnelManager.isSupported` are `package`, and
  `XrayDocumentBuilder`'s tags are internal.

### Fixed

- After a start that failed or timed out, a refused save of the profile with on-demand off is tried once more and
  logged, instead of being dropped silently with on-demand left on.

### Removed

- `NetworkModel.current`, `NetworkModel.save()` and `TunnelConfigDirectories.network`: the proxy providers run with
  `NetworkModel.default`, the only value ever stored.

## 0.2.0 (2026-10-12)

The engines are those of 0.1.0.

### Added

- `TunnelManager.connectedNode()`: the address or host name of the node the running tunnel connects to, as the
  tunnel's provider recorded it, or nil while the tunnel is down.
- `TunnelManager.restart()` starts the tunnel again on the node it last used, with the DNS and obfuscation settings
  as they are now, without new credentials. With nothing stored to start from, it throws the new
  `TunnelsServiceError.noStoredConfiguration` and leaves the tunnel as it is.

### Fixed

- macOS split tunnelling: an app's helper processes follow the app. A flow whose signing identifier extends a selected
  app's with a dot (`com.example.app.helper`) counts as that app's.
- A request is tried when the network path requires a connection, such as an on-demand VPN coming up, instead of
  failing at once as offline.
- macOS: with split tunnelling on, Hysteria 2 connects. The split-tunnel proxy was offered the tunnel's own UDP flow to
  its node and declined it, which broke the socket. The tunnels now record their node, and the proxy leaves its
  addresses out of its rules.
- A request now ends within its own timeout across the primary and the mirrors. A primary that answered with a server
  error and a mirror that did not answer used to add up to minutes for one request, as each mirror attempt waited the
  full timeout. At the deadline the request ends with the primary's answer, or with a timeout.
- Xray and V2Ray connections go to the address the device looked up through its own DNS. The client used to hand the
  node each sniffed site name, so the node looked it up again with its own resolver and used that answer instead;
  sniffing now only chooses routes (`routeOnly`).

## 0.1.0

The first release: the DVPN SDK API client and the WireGuard/AmneziaWG, Xray and Hysteria 2 tunnels in one package,
with the engines as prebuilt release assets.
