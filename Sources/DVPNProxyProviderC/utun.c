//
//  utun.c
//  DVPNCore
//

#include "DVPNProxyProviderC.h"

#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

// The kernel-control declarations of <sys/kern_control.h>, which the iOS and tvOS SDKs do not ship.
// Their layout is the kernel's ABI.
#ifndef AF_SYSTEM
#define AF_SYSTEM 32
#endif

struct dvpn_ctl_info {
    uint32_t ctl_id;
    char ctl_name[96];
};

struct dvpn_sockaddr_ctl {
    uint8_t sc_len;
    uint8_t sc_family;
    uint16_t ss_sysaddr;
    uint32_t sc_id;
    uint32_t sc_unit;
    uint32_t sc_reserved[5];
};

// _IOWR('N', 3, struct ctl_info)
#define DVPN_CTLIOCGINFO 0xc0644e03UL

int dvpn_utun_file_descriptor(void) {
    struct dvpn_ctl_info info;
    memset(&info, 0, sizeof(info));
    strlcpy(info.ctl_name, "com.apple.net.utun_control", sizeof(info.ctl_name));
    int resolved = 0;

    for (int fd = 0; fd <= 1024; fd++) {
        struct dvpn_sockaddr_ctl address;
        socklen_t length = sizeof(address);
        if (getpeername(fd, (struct sockaddr *)&address, &length) != 0 || address.sc_family != AF_SYSTEM) {
            continue;
        }
        // The control's ID is the kernel's, asked once through the first kernel-control socket.
        if (!resolved) {
            if (ioctl(fd, DVPN_CTLIOCGINFO, &info) != 0) {
                continue;
            }
            resolved = 1;
        }
        if (address.sc_id == info.ctl_id) {
            return fd;
        }
    }
    return -1;
}
