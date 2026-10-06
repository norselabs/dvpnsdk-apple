//
//  DVPNProxyProviderC.h
//  DVPNCore
//

#ifndef DVPN_PROXY_PROVIDER_C_H
#define DVPN_PROXY_PROVIDER_C_H

/// The file descriptor of the utun interface NetworkExtension created for this packet tunnel, found
/// by scanning the process's descriptors for the utun control socket; -1 when there is none.
/// hev-socks5-tunnel reads and writes the packets through it.
int dvpn_utun_file_descriptor(void);

#endif
