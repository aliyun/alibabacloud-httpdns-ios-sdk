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
ALICLOUD_HTTPDNS_FIELD_TTL              @" NUMBERIC NOT NULL, "                \
ALICLOUD_HTTPDNS_FIELD_REGION           @" TEXT "                               \
@")"

#define ALICLOUD_HTTPDNS_SQL_CLEAN_IP6_RECORD_TABLE                        \
        @"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD  @" "            \


#define ALICLOUD_HTTPDNS_SQL_INSERT_IP6_RECORD                              \
@"INSERT OR REPLACE INTO " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD     @" ("  \
ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID      @", "                  \
ALICLOUD_HTTPDNS_FIELD_IP                  @", "                  \
ALICLOUD_HTTPDNS_FIELD_TTL                 @", "                   \
ALICLOUD_HTTPDNS_FIELD_REGION                                        \
@") VALUES( ?, ?, ?, ?)"

#define ALICLOUD_HTTPDNS_SQL_DELETE_IP6_RECORD                 \
@"DELETE FROM " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD    @" "  \
@"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"

#define ALICLOUD_HTTPDNS_SQL_SELECT_IP6_RECORD                   \
@"SELECT * FROM " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD    @" "  \
@"WHERE " ALICLOUD_HTTPDNS_FIELD_HOST_RECORD_ID     @" = ?"


//判断当前表中是否存在region列
#define ALICLOUD_HTTPDNS_SQL_FIND_IP6_REGION  \
    @"SELECT * FROM sqlite_master WHERE name='" ALICLOUD_HTTPDNS_TABLE_IP6_RECORD @"' and sql like '%" ALICLOUD_HTTPDNS_FIELD_REGION @"%'"



//给IP表增加REGION列
#define ALICLOUD_HTTPDNS_SQL_ADD_IP_COLUMN_IP6_REGION \
    @"ALTER TABLE " ALICLOUD_HTTPDNS_TABLE_IP6_RECORD @" ADD COLUMN '" ALICLOUD_HTTPDNS_FIELD_REGION @"' TEXT"



#endif /* HttpdnsIP6CacheStoreSQL_h */
