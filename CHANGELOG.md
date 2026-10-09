# Changelog

Changes that apps can notice, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The
versions follow [Semantic Versioning](https://semver.org); until 1.0.0 a minor version may change the API.

## Unreleased

### Added

- `TunnelManager.restart()` starts the tunnel again on the node it last used, with the DNS and obfuscation settings
  as they are now, without new credentials. With nothing stored to start from, it throws the new
  `TunnelsServiceError.noStoredConfiguration` and leaves the tunnel as it is.

### Fixed

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
