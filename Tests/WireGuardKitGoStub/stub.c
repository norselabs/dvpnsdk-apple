// The Go engine's C API with no engine behind it, for `swift test` (scripts/test.sh): a test binary can hold only
// one Go runtime, and the Xray tests link LibXray's. No test starts a WireGuard tunnel.

#include "wireguard.h"

void wgSetLogger(void *context, logger_fn_t logger_fn) {}
int wgTurnOn(const char *settings, int32_t tun_fd) { return -1; }
void wgTurnOff(int handle) {}
int64_t wgSetConfig(int handle, const char *settings) { return -1; }
char *wgGetConfig(int handle) { return 0; }
void wgBumpSockets(int handle) {}
void wgDisableSomeRoamingForBrokenMobileSemantics(int handle) {}
const char *wgVersion(void) { return "stub"; }
