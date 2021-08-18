//
//  HttpdnsIPCacheStoreSQL.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/8.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsIPCacheStoreSQL_h
#define HttpdnsIPCacheStoreSQL_h

#define ALICLOUD_HTTPDNS_TABLE_IP_RECORD            @"IPRecord"

#define ALICLOUD_HTTPDNS_FIELD_IP_RECORD_ID         @"IPRecord_id"
#define ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID       @"hostRecord_id"
#define ALICLOUD_HTTPDNS_FIELD_IP                   @"IP"
#define ALICLOUD_HTTPDNS_FIELD_TTL                  @"ttl"

#define ALICLOUD_HTTPDNS_SQL_CREATE_IP_RECORD_TABLE                                 \
    @"CREATE TABLE IF NOT EXISTS " ALICLOUD_HTTPDNS_TABLE_IP_RECORD    @" ("           \
        ALICLOUD_HTTPDNS_FIELD_IP_RECORD_ID     @" INTEGER PRIMARY KEY AUTOINCREMENT, "\
        ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID   @" TEXT NOT NULL, "                    \
        ALICLOUD_HTTPDNS_FIELD_IP               @" TEXT NOT NULL, "                    \
        ALICLOUD_HTTPDNS_FIELD_TTL              @" NUMBERIC NOT NULL"                \
    @")"


#define ALICLOUD_HTTPDNS_SQL_CLEAN_IP_RECORD_TABLE                        \
        @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_IP_RECORD  @" "            \


#define ALICLOUD_HTTPDNS_SQL_INSERT_IP_RECORD                              \
    @"INSERT OR REPLACE INTO " ALICLOUD_HTTPDNS_TABLE_IP_RECORD     @" ("  \
         ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID      @", "                  \
         ALICLOUD_HTTPDNS_FIELD_IP                  @", "                  \
         ALICLOUD_HTTPDNS_FIELD_TTL                                        \
    @") VALUES( ?, ?, ?)"

#define ALICLOUD_HTTPDNS_SQL_DELETE_IP_RECORD                 \
    @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_IP_RECORD    @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_IP_RECORD                   \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_IP_RECORD    @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"

#endif /* HttpdnsIPCacheStoreSQL_h */
