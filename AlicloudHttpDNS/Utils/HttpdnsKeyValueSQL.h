//
//  HttpdnsHostRecord.h
//  AlicloudHttpDNS
//
//  Created by ElonChan（地风） on 2017/5/3.
//  Copyright © 2017年 alibaba-inc.com. All rights reserved.
//


#ifndef ALICLOUD_HTTPDNS_KeyValueSQL_h
#define ALICLOUD_HTTPDNS_KeyValueSQL_h

#define ALICLOUD_HTTPDNS_TABLE_KEY_VALUE @"key_value_table"
#define ALICLOUD_HTTPDNS_FIELD_KEY       @"key"
#define ALICLOUD_HTTPDNS_FIELD_VALUE     @"value"

#define ALICLOUD_HTTPDNS_SQL_CREATE_KEY_VALUE_TABLE_FMT  \
    @"CREATE TABLE IF NOT EXISTS %@ ("     \
        ALICLOUD_HTTPDNS_FIELD_KEY   @" TEXT, "          \
        ALICLOUD_HTTPDNS_FIELD_VALUE @" BLOB, "          \
        @"PRIMARY KEY(" ALICLOUD_HTTPDNS_FIELD_KEY @")"  \
    @")"

#define ALICLOUD_HTTPDNS_SQL_SELECT_KEY_VALUE_FMT  \
    @"SELECT * FROM %@ WHERE " ALICLOUD_HTTPDNS_FIELD_KEY @" = ?"

#define ALICLOUD_HTTPDNS_SQL_UPDATE_KEY_VALUE_FMT               \
    @"INSERT OR REPLACE INTO %@ "                 \
    @"(" ALICLOUD_HTTPDNS_FIELD_KEY @", " ALICLOUD_HTTPDNS_FIELD_VALUE @") "  \
    @"VALUES(?, ?)"

#define ALICLOUD_HTTPDNS_SQL_DELETE_KEY_VALUE_FMT  \
    @"DELETE FROM %@ WHERE " ALICLOUD_HTTPDNS_FIELD_KEY @" = ?"

#endif
