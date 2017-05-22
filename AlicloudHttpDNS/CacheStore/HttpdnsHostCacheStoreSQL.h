//
//  HttpdnsHostCacheStoreSQL.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//

#ifndef HttpdnsHostCacheStoreSQL_h
#define HttpdnsHostCacheStoreSQL_h

#define ALICLOUD_HTTPDNS_TABLE_HOST_RECORD          @"HostRecord"

#define ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID       @"hostRecord_id"
#define ALICLOUD_HTTPDNS_FIELD_HOST                 @"host"
#define ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @"carrier"
#define ALICLOUD_HTTPDNS_FIELD_CREATE_AT            @"create_at"
#define ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT            @"expire_at"

#define ALICLOUD_HTTPDNS_SQL_CREATE_HOST_RECORD_TABLE                        \
    @"CREATE TABLE IF NOT EXISTS " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" ("  \
        ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID       @" INTEGER PRIMARY KEY AUTOINCREMENT, "            \
        ALICLOUD_HTTPDNS_FIELD_HOST                 @" TEXT, "                \
        ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @" TEXT, "                \
        ALICLOUD_HTTPDNS_FIELD_CREATE_AT            @" REAL, "                \
        ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT            @" REAL, "                 \
        @"UNIQUE (" ALICLOUD_HTTPDNS_FIELD_HOST @", " ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER @")"           \
    @")"

#define ALICLOUD_HTTPDNS_SQL_INSERT_HOST_RECORD                            \
    @"INSERT OR REPLACE INTO " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD   @" ("  \
        ALICLOUD_HTTPDNS_FIELD_HOST                 @", "                  \
        ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @", "                  \
        ALICLOUD_HTTPDNS_FIELD_CREATE_AT            @", "                  \
        ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT                                   \
    @") VALUES( ?, ?, ?, ?)"

#define ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD                 \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD_WITH_CARRIER    \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_HOST_RECORD_WITH_HOST_AND_CARRIER    \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD    @" "         \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST                   @" = ?"  @" "\
    @"AND " ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER          @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_EXPIRED_HOST_RECORD        \
    @"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_EXPIRE_AT @" <= ?"

#define ALICLOUD_HTTPDNS_SQL_DELETE_HOST_RECORD_WITH_HOST_ID     \
    @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "     \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID @" = ?"

#define ALICLOUD_HTTPDNS_SQL_DELETE_HOST_RECORD_WITH_HOST     \
    @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "  \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST @" = ?"

#define ALICLOUD_HTTPDNS_SQL_DELETE_HOST_RECORD_WITH_HOST_AND_CARRIER   \
    @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_HOST_RECORD  @" "            \
    @"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST               @" = ?"  @" "   \
    @"AND " ALICLOUD_HTTPDNS_FIELD_SERVICE_CARRIER      @" = ?"

#endif /* HttpdnsHostCacheStoreSQL_h */
