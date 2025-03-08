//
//  socket_udp.h
//  ALINetworkSDK
//
//  Created by wuchen.xj on 2017/3/30.
//  Copyright © 2017年 wuchen.xj. All rights reserved.
//


#ifndef __SOCKET_UDP_H__
#define __SOCKET_UDP_H__

#ifdef __cplusplus
extern "C" {
#endif

    /**
     * test_udp_connect_ipv6() :
     * return value :
     *    1 : success
     *    0 : failure
     */
    int test_udp_connect_ipv6(void);

    /**
     * test_udp_connect_ipv4() :
     * return value :
     *    1 : success
     *    0 : failure
     */
    int test_udp_connect_ipv4(void);

#ifdef __cplusplus
}
#endif

#endif
