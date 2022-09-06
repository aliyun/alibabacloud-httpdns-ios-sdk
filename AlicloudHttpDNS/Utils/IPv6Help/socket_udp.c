//
//  NWAutoLock.h
//  ALINetworkSDK
//
//  Created by wuchen.xj on 2017/3/30.
//  Copyright © 2017年 wuchen.xj. All rights reserved.
//

#include <sys/socket.h>
#include <sys/select.h>
#include <sys/uio.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <net/if.h>
#include <unistd.h>
#include <stdint.h>
#include <memory.h>

#include <TargetConditionals.h>

typedef union sockaddr_union {
    struct sockaddr     generic;
    struct sockaddr_in  in;
    struct sockaddr_in6 in6;
} sockaddr_union;

/*
 * Connect a UDP socket to a given unicast address. This will cause no network
 * traffic, but will fail fast if the system has no or limited reachability to
 * the destination (e.g., no IPv4 address, no IPv6 default route, ...).
 */
static const unsigned int kMaxLoopCount = 10;
static int _test_udp_connect(int pf, struct sockaddr *addr, socklen_t addrlen) {
    int s = socket(pf, SOCK_DGRAM, IPPROTO_UDP);
    if (s < 0)
        return 0;
    
    int ret;
    unsigned int loop_count = 0;
    do {
        ret = connect(s, addr, addrlen);
    } while (ret < 0 && errno == EINTR && loop_count++<kMaxLoopCount);

    int success = (ret == 0);

    loop_count = 0;
    do {
        ret = close(s);
    } while (ret < 0 && errno == EINTR && loop_count++<kMaxLoopCount);

    return success;
}

/*
 * The following functions determine whether IPv4 or IPv6 connectivity is
 * available in order to implement AI_ADDRCONFIG.
 *
 * Strictly speaking, AI_ADDRCONFIG should not look at whether connectivity is
 * available, but whether addresses of the specified family are "configured
 * on the local system". However, bionic doesn't currently support getifaddrs,
 * so checking for connectivity is the next best thing.
 */
int test_udp_connect_ipv6(void) {
    static const struct sockaddr_in6 sin6_test = {
        .sin6_len = sizeof(struct sockaddr_in6),
        .sin6_family = AF_INET6,
        .sin6_port = 80,
        .sin6_flowinfo = 0,
        .sin6_scope_id = 0,
        .sin6_addr.s6_addr = {  // 2000::
            0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
    };
    sockaddr_union addr = { .in6 = sin6_test };
    return _test_udp_connect(PF_INET6, &addr.generic, sizeof(addr.in6));
}

int test_udp_connect_ipv4(void) {
    static const struct sockaddr_in sin_test = {
        .sin_len = sizeof(struct sockaddr_in),
        .sin_family = AF_INET,
        .sin_port = 80,
        .sin_addr.s_addr = htonl(0x08080808L),  // 8.8.8.8
    };
    sockaddr_union addr = { .in = sin_test };
    return _test_udp_connect(PF_INET, &addr.generic, sizeof(addr.in));
}
