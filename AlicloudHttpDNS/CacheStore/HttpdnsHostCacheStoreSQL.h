//
//  HttpdnsHostCacheStoreSQL.h
//  AlicloudHttpDNS
//
//  Created by chenyilong on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsHostCacheStoreSQL_h
#define HttpdnsHostCacheStoreSQL_h
/*!
 *
 Field	Type	Desc
 1. id	INTEGER	自增id
 2. host	TEXT	域名
 3. Carrier	TEXT	运营商
 4. time	TEXT	查询时间(单位：秒)
 5. IPs
 */
#define ALICLOUD_HTTPDNS_TABLE_HOST_RECORD          @"HostRecord"

#define ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID       @"HostRecord_id"
#define ALICLOUD_HTTPDNS_FIELD_HOST                 @"host"
#define ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @"carrier"
#define ALICLOUD_HTTPDNS_FIELD_TIMESTAMP            @"timestamp"
#define ALICLOUD_HTTPDNS_FIELD_IPS                  @"ips"

#define ALICLOUD_HTTPDNS_SQL_CREATE_CONVERSATION_TABLE                        \
    @"CREATE TABLE IF NOT EXISTS " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" ("  \
        ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID       @" INTEGER PRIMARY KEY AUTOINCREMENT, "            \
        ALICLOUD_HTTPDNS_FIELD_HOST                 @" TEXT NOT NULL, "                \
        ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @" TEXT NOT NULL, "                \
        ALICLOUD_HTTPDNS_FIELD_TIMESTAMP            @" NUMBERIC NOT NULL, "            \
        ALICLOUD_HTTPDNS_FIELD_IPS                  @" BLOB NOT NULL"                \
    @")"

#define ALICLOUD_HTTPDNS_SQL_INSERT_CONVERSATION                           \
    @"INSERT OR REPLACE INTO " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD   @" ("  \
        ALICLOUD_HTTPDNS_FIELD_HOST                 @", "                  \
        ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @", "                  \
        ALICLOUD_HTTPDNS_FIELD_TIMESTAMP            @", "                  \
        ALICLOUD_HTTPDNS_FIELD_IPS                                         \
    @") VALUES( ?, ?, ?, ?)"

#define ALICLOUD_HTTPDNS_SQL_DELETE_CONVERSATION              \
    @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_CONVERSATION_ID @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_CONVERSATION                \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_CONVERSATION_ID @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_EXPIRED_CONVERSATIONS       \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT @" <= ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_ALIVE_CONVERSATIONS         \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT @" > ?"

#endif /* HttpdnsHostCacheStoreSQL_h */
