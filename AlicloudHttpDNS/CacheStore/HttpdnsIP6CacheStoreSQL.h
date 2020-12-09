//
//  HttpdnsIP6CacheStoreSQL.h
//  AlicloudHttpDNS
//
//  Created by junmo on 2019/2/25.
//  Copyright © 2019年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsIP6CacheStoreSQL_h
#define HttpdnsIP6CacheStoreSQL_h

#define ALICLOUD_HTTPDNS_TABLE_IP6_RECORD            @"IP6Record"

#define ALICLOUD_HTTPDNS_SQL_CREATE_IP6_RECORD_TABLE                                 \
@"CREATE TABLE IF NOT EXISTS " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD    @" ("           \
ALICLOUD_HTTPDNS_FIELD_IP_RECORD_ID     @" INTEGER PRIMARY KEY AUTOINCREMENT, "\
ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID   @" TEXT NOT NULL, "                    \
ALICLOUD_HTTPDNS_FIELD_IP               @" TEXT NOT NULL, "                    \
ALICLOUD_HTTPDNS_FIELD_TTL              @" NUMBERIC NOT NULL"                \
@")"

#define ALICLOUD_HTTPDNS_SQL_INSERT_IP6_RECORD                              \
@"INSERT OR REPLACE INTO " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD     @" ("  \
ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID      @", "                  \
ALICLOUD_HTTPDNS_FIELD_IP                  @", "                  \
ALICLOUD_HTTPDNS_FIELD_TTL                                        \
@") VALUES( ?, ?, ?)"

#define ALICLOUD_HTTPDNS_SQL_DELETE_IP6_RECORD                 \
@"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD    @" "  \
@"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_IP6_RECORD                   \
@"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD    @" "  \
@"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"

#endif /* HttpdnsIP6CacheStoreSQL_h */
