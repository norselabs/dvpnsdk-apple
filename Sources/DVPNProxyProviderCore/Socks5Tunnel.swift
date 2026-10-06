//
//  Socks5Tunnel.swift
//  DVPNCore
//

import DVPNProxyProviderC
import HevSocks5Tunnel

// MARK: - Socks5Tunnel

/// hev-socks5-tunnel (`scripts/build-hev.sh`), which moves the utun packets to the local SOCKS5
/// proxy. Replaces the Tun2SocksKit package, which carried no licence.
enum Socks5Tunnel {
    /// The utun interface of this packet tunnel; nil before its network settings are applied.
    static var tunnelFileDescriptor: Int32? {
        let descriptor = dvpn_utun_file_descriptor()
        return descriptor >= 0 ? descriptor : nil
    }

    /// Runs hev-socks5-tunnel with the configuration file at `path` on `descriptor` until it stops,
    /// blocking the calling thread; returns its exit code.
    static func run(configurationPath path: String, descriptor: Int32) -> Int32 {
        hev_socks5_tunnel_main(path, descriptor)
    }
}
