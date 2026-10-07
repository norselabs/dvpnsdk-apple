# Changelog

Changes that apps can notice, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The
versions follow [Semantic Versioning](https://semver.org); until 1.0.0 a minor version may change the API.

## Unreleased

### Added

- `TunnelManager.restart()` starts the tunnel again on the node it last used, with the DNS and obfuscation settings
  as they are now, without new credentials. With nothing stored to start from, it throws the new
  `TunnelsServiceError.noStoredConfiguration` and leaves the tunnel as it is.

## 0.1.0

The first release: the DVPN SDK API client and the WireGuard/AmneziaWG, Xray and Hysteria 2 tunnels in one package,
with the engines as prebuilt release assets.
