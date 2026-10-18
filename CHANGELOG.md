# Changelog

Changes that apps can notice, newest first, in the style of [Keep a Changelog](https://keepachangelog.com). The
versions follow [Semantic Versioning](https://semver.org); until 1.0.0 a minor version may change the API.

## Unreleased

### Added

- `TunnelNetworkOptions`, returned by `TunnelSettingsProviding.networkOptions` (`.default` unless an app returns its
  own): the kill switch (`includeAllNetworks`), local networks (`excludeLocalNetworks`) and enforced routes
  (`enforceRoutes`), on every engine's profile alike. They apply when the profile is saved, so a running tunnel needs a
  `restart()`. The default leaves each profile as before: WireGuard's with the system's default for local networks,
  Xray's and Hysteria's excluding them.
- `TunnelNetworkOptions.ipv6`: `.tunnel` sends all IPv6 into the tunnel instead of around it. A WireGuard tunnel takes
  `::/0` and the IPv6 address the node assigned, or a unique local placeholder the node drops when it assigned none;
  the Xray and Hysteria providers run with IPv6 enabled, which the app now stores for them
  (`TunnelConfigDirectories.storeNetwork`). `.unchanged`, the default, routes IPv6 as before.
- `WireGuardEndpoint.clientAddresses`: every address the node assigned the client, its IPv6 address included; the
  decoder used to keep the first only.
- `DNSConfiguration` and `TunnelSettingsProviding.dnsConfiguration`: a tunnel's resolvers as servers and an optional
  DNS-over-HTTPS URL, applied through `NEDNSOverHTTPSSettings` by the WireGuard extension and the proxy providers
  alike. Presets with each provider's IPv4 and IPv6 addresses and DoH endpoint: Cloudflare (standard, malware
  blocking, family), Quad9, AdGuard (default, family) and Google, in `DNSConfiguration.presets`; `custom(...)` for an
  app's own; `unencrypted` for plain DNS. IPv6 servers are used only with `ipv6: .tunnel`. The Mullvad presets are
  deprecated already: Mullvad ends that service on 2 November 2026. `DNSServerType` stays, as
  `DNSServerType.configuration` (its servers in plain DNS), and a stored `DNSServerType` decodes as a
  `DNSConfiguration`. `selectedDNS` now has a default, so an app may implement `dnsConfiguration` alone.
- WireGuardKit: `InterfaceConfiguration.dnsOverHTTPSURL`, stored as a `DNSOverHTTPS` key in the configuration text.
- `TunnelManager.switchNode(to:)`: moves a running tunnel to the node in new credentials. On the same engine the
  extension changes nodes in place, keeping the tunnel interface and its routes, so traffic waits for the new node
  instead of going around the tunnel: the WireGuard provider updates its engine (`WireGuardAdapter.update`), the Xray
  and Hysteria providers restart their engine alone behind the same hev-socks5-tunnel. A node that does not answer, or
  an engine that cannot start on it, leaves the tunnel up. Otherwise (the tunnel is down, another engine runs, or the
  extension predates the message) it stops the tunnel and starts it from the credentials. The providers answer the
  new `switchNode` app message; one built before it answers nothing, and the app falls back to the full start.

### Changed

- The split-tunnel proxy's warning about a flow with no physical interface no longer names the app; a debug line,
  which the log file never holds, does.
- The API client logs under the host app's bundle identifier, like the tunnel layer, instead of `com.dvpnsdk`, so a
  log an app reads by its subsystem has the requests too.
- `MirroredTransport` logs one line per request at the notice level, which the system keeps: the method, the path,
  the status and the backend's error code or the failure, and the time it took. In this line and the transport's
  others, a path segment that is not a word (an ID an app put in the path) shows as "…".
- A fallback to a mirror is logged at the notice level instead of info.
- `SplitTunnelManager` says that its calls must not overlap or be cancelled: a call pauses inside, so a newer one made
  in that pause can be overtaken by it, and a cancelled one can start a proxy that is still stopping.

### Fixed

- `TunnelManager.connectedNode()` returns the node on iOS and tvOS too: the tunnel providers recorded it on macOS only.
- A proxy engine's start reason, which the provider records for the app, and Xray's start error keep the SDK error's
  own words (its `description`) instead of "The operation couldn't be completed", which they read since the errors
  stopped being `LocalizedError`s.
- `WireGuardAdapter.start` builds without the "'weak' ownership of capture 'self'" warning that recent Swift
  compilers give in every app that builds the package.
- An app that declares no WireGuard extension no longer traps when `TunnelManager` loads its tunnels. WireGuard and
  AmneziaWG credentials then fail at `start(from:)` with `TunnelsServiceError.unsupportedProtocol`, as the other
  engines' do, and `NETunnelProviderProtocol(tunnelConfiguration:)` returns nil instead of trapping.
- A WireGuard start rewrites a profile that still points at a proxy engine's extension even when the WireGuard
  configuration is the one stored before; it used to keep the proxy's extension.

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
