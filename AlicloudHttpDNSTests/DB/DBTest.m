//
//  DBTest.m
//  AlicloudHttpDNSTests
//
//  Created by xuyecan on 2025/3/15.
//  Copyright © 2025 alibaba-inc.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../Testbase/TestBase.h"
#import "HttpdnsDB.h"
#import "HttpdnsHostRecord.h"

@interface DBTest : TestBase

@property (nonatomic, strong) HttpdnsDB *db;
@property (nonatomic, assign) NSInteger testAccountId;

@end

@implementation DBTest

- (void)setUp {
    [super setUp];

    // Use a test-specific account ID to avoid conflicts with real data
    self.testAccountId = 999999;
    self.db = [[HttpdnsDB alloc] initWithAccountId:self.testAccountId];

    // Clean up any existing data
    [self.db deleteAll];
}

- (void)tearDown {
    // Clean up after tests
    [self.db deleteAll];
    self.db = nil;

    [super tearDown];
}

#pragma mark - Initialization Tests

- (void)testInitialization {
    XCTAssertNotNil(self.db, @"Database should be initialized successfully");

    // Test with invalid account ID (negative value)
    HttpdnsDB *invalidDB = [[HttpdnsDB alloc] initWithAccountId:-1];
    XCTAssertNotNil(invalidDB, @"Database should still initialize with negative account ID");
}

#pragma mark - Create Tests

- (void)testCreateRecord {
    // Create a test record
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"test.example.com" cacheKey:@"test_cache_key"];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed");

    // Verify the record was created by querying it
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"test_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the created record");
    XCTAssertEqualObjects(fetchedRecord.cacheKey, @"test_cache_key", @"Cache key should match");
    XCTAssertEqualObjects(fetchedRecord.hostName, @"test.example.com", @"Hostname should match");
    XCTAssertEqualObjects(fetchedRecord.clientIp, @"192.168.1.1", @"Client IP should match");
    XCTAssertEqual(fetchedRecord.v4ips.count, 2, @"Should have 2 IPv4 addresses");
    XCTAssertEqual(fetchedRecord.v6ips.count, 1, @"Should have 1 IPv6 address");
}

- (void)testCreateMultipleRecords {
    // Create multiple test records
    NSArray<NSString *> *hostnames = @[@"host1.example.com", @"host2.example.com", @"host3.example.com"];
    NSArray<NSString *> *cacheKeys = @[@"cache_key_1", @"cache_key_2", @"cache_key_3"];

    for (NSInteger i = 0; i < hostnames.count; i++) {
        HttpdnsHostRecord *record = [self createTestRecordWithHostname:hostnames[i] cacheKey:cacheKeys[i]];
        BOOL result = [self.db createOrUpdate:record];
        XCTAssertTrue(result, @"Record creation should succeed for %@", hostnames[i]);
    }

    // Verify all records were created
    for (NSInteger i = 0; i < cacheKeys.count; i++) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKeys[i]];
        XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the created record for %@", cacheKeys[i]);
        XCTAssertEqualObjects(fetchedRecord.cacheKey, cacheKeys[i], @"Cache key should match");
        XCTAssertEqualObjects(fetchedRecord.hostName, hostnames[i], @"Hostname should match");
    }
}

- (void)testCreateRecordWithNilCacheKey {
    // Create a record with nil cacheKey
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"test.example.com" cacheKey:nil];

    // Attempt to insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertFalse(result, @"Record creation should fail with nil cacheKey");
}

- (void)testCreateRecordWithEmptyValues {
    // Create a record with empty arrays and nil values
    HttpdnsHostRecord *record = [[HttpdnsHostRecord alloc] initWithId:1
                                                             cacheKey:@"empty_cache_key"
                                                             hostName:@"empty.example.com"
                                                             createAt:nil
                                                             modifyAt:nil
                                                             clientIp:nil
                                                                v4ips:@[]
                                                                v4ttl:0
                                                         v4LookupTime:0
                                                                v6ips:@[]
                                                                v6ttl:0
                                                         v6LookupTime:0
                                                                extra:@""];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed with empty values");

    // Verify the record was created
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"empty_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the created record");
    XCTAssertEqualObjects(fetchedRecord.cacheKey, @"empty_cache_key", @"Cache key should match");
    XCTAssertEqualObjects(fetchedRecord.hostName, @"empty.example.com", @"Hostname should match");
    XCTAssertNil(fetchedRecord.clientIp, @"Client IP should be nil");
    XCTAssertEqual(fetchedRecord.v4ips.count, 0, @"Should have 0 IPv4 addresses");
    XCTAssertEqual(fetchedRecord.v6ips.count, 0, @"Should have 0 IPv6 addresses");

    // Verify createAt and modifyAt were automatically set
    XCTAssertNotNil(fetchedRecord.createAt, @"createAt should be automatically set");
    XCTAssertNotNil(fetchedRecord.modifyAt, @"modifyAt should be automatically set");
}

- (void)testCreateMultipleRecordsWithSameHostname {
    // Create multiple records with the same hostname but different cache keys
    NSString *hostname = @"same.example.com";
    NSArray<NSString *> *cacheKeys = @[@"same_cache_key_1", @"same_cache_key_2", @"same_cache_key_3"];

    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *record = [self createTestRecordWithHostname:hostname cacheKey:cacheKey];
        BOOL result = [self.db createOrUpdate:record];
        XCTAssertTrue(result, @"Record creation should succeed for %@", cacheKey);
    }

    // Verify all records were created
    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the created record for %@", cacheKey);
        XCTAssertEqualObjects(fetchedRecord.cacheKey, cacheKey, @"Cache key should match");
        XCTAssertEqualObjects(fetchedRecord.hostName, hostname, @"Hostname should match");
    }
}

#pragma mark - Update Tests

- (void)testUpdateRecord {
    // Create a test record
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"update.example.com" cacheKey:@"update_cache_key"];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed");

    // Fetch the record to get its createAt timestamp
    HttpdnsHostRecord *originalRecord = [self.db selectByCacheKey:@"update_cache_key"];
    NSDate *originalCreateAt = originalRecord.createAt;
    NSDate *originalModifyAt = originalRecord.modifyAt;

    // Wait a moment to ensure timestamps will be different
    [NSThread sleepForTimeInterval:0.1];

    // Update the record with new values
    HttpdnsHostRecord *updatedRecord = [[HttpdnsHostRecord alloc] initWithId:originalRecord.id
                                                                    cacheKey:@"update_cache_key"
                                                                    hostName:@"updated.example.com" // Changed hostname
                                                                    createAt:[NSDate date] // Try to change createAt
                                                                    modifyAt:[NSDate date]
                                                                    clientIp:@"10.0.0.1" // Changed
                                                                       v4ips:@[@"10.0.0.2", @"10.0.0.3"] // Changed
                                                                       v4ttl:600 // Changed
                                                                v4LookupTime:originalRecord.v4LookupTime + 1000
                                                                       v6ips:@[@"2001:db8::1", @"2001:db8::2"] // Changed
                                                                       v6ttl:1200 // Changed
                                                                v6LookupTime:originalRecord.v6LookupTime + 1000
                                                                       extra:@"updated"]; // Changed

    // Update the record
    result = [self.db createOrUpdate:updatedRecord];
    XCTAssertTrue(result, @"Record update should succeed");

    // Fetch the updated record
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"update_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the updated record");

    // Verify the updated values
    XCTAssertEqualObjects(fetchedRecord.hostName, @"updated.example.com", @"Hostname should be updated");
    XCTAssertEqualObjects(fetchedRecord.clientIp, @"10.0.0.1", @"Client IP should be updated");
    XCTAssertEqual(fetchedRecord.v4ips.count, 2, @"Should have 2 IPv4 addresses");
    XCTAssertEqualObjects(fetchedRecord.v4ips[0], @"10.0.0.2", @"IPv4 address should be updated");
    XCTAssertEqual(fetchedRecord.v4ttl, 600, @"v4ttl should be updated");
    XCTAssertEqual(fetchedRecord.v6ips.count, 2, @"Should have 2 IPv6 addresses");
    XCTAssertEqual(fetchedRecord.v6ttl, 1200, @"v6ttl should be updated");
    XCTAssertEqualObjects(fetchedRecord.extra, @"updated", @"Extra data should be updated");

    // Verify createAt was preserved and modifyAt was updated
    XCTAssertEqualWithAccuracy([fetchedRecord.createAt timeIntervalSince1970],
                              [originalCreateAt timeIntervalSince1970],
                              0.001,
                              @"createAt should not change on update");

    XCTAssertTrue([fetchedRecord.modifyAt timeIntervalSinceDate:originalModifyAt] > 0,
                 @"modifyAt should be updated to a later time");
}

- (void)testUpdateNonExistentRecord {
    // Create a record that doesn't exist in the database
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"nonexistent.example.com" cacheKey:@"nonexistent_cache_key"];

    // Update (which should actually create) the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"createOrUpdate should succeed for non-existent record");

    // Verify the record was created
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"nonexistent_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the created record");
}

#pragma mark - Query Tests

- (void)testSelectByCacheKey {
    // Create a test record
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"query.example.com" cacheKey:@"query_cache_key"];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed");

    // Query the record
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"query_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the record");
    XCTAssertEqualObjects(fetchedRecord.cacheKey, @"query_cache_key", @"Cache key should match");
    XCTAssertEqualObjects(fetchedRecord.hostName, @"query.example.com", @"Hostname should match");
}

- (void)testSelectNonExistentRecord {
    // Query a record that doesn't exist
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"nonexistent_cache_key"];
    XCTAssertNil(fetchedRecord, @"Should return nil for non-existent record");
}

- (void)testSelectWithNilCacheKey {
    // Query with nil cacheKey
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:nil];
    XCTAssertNil(fetchedRecord, @"Should return nil for nil cacheKey");
}

#pragma mark - Delete Tests

- (void)testDeleteByCacheKey {
    // Create a test record
    HttpdnsHostRecord *record = [self createTestRecordWithHostname:@"delete.example.com" cacheKey:@"delete_cache_key"];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed");

    // Verify the record exists
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"delete_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Record should exist before deletion");

    // Delete the record
    result = [self.db deleteByCacheKey:@"delete_cache_key"];
    XCTAssertTrue(result, @"Record deletion should succeed");

    // Verify the record was deleted
    fetchedRecord = [self.db selectByCacheKey:@"delete_cache_key"];
    XCTAssertNil(fetchedRecord, @"Record should be deleted");
}

- (void)testDeleteByHostname {
    // Create multiple records with the same hostname but different cache keys
    NSString *hostname = @"delete_multiple.example.com";
    NSArray<NSString *> *cacheKeys = @[@"delete_cache_key_1", @"delete_cache_key_2", @"delete_cache_key_3"];

    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *record = [self createTestRecordWithHostname:hostname cacheKey:cacheKey];
        [self.db createOrUpdate:record];
    }

    // Verify records exist
    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNotNil(fetchedRecord, @"Record should exist before deletion");
    }

    // Delete all records with the same hostname
    BOOL result = [self.db deleteByHostNameArr:@[hostname]];
    XCTAssertTrue(result, @"Deleting records by hostname should succeed");

    // Verify all records were deleted
    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNil(fetchedRecord, @"Record should be deleted");
    }
}

- (void)testDeleteNonExistentRecord {
    // Delete a record that doesn't exist
    BOOL result = [self.db deleteByCacheKey:@"nonexistent_cache_key"];
    XCTAssertTrue(result, @"Deleting non-existent record should still return success");
}

- (void)testDeleteWithNilCacheKey {
    // Delete with nil cacheKey
    BOOL result = [self.db deleteByCacheKey:nil];
    XCTAssertFalse(result, @"Deleting with nil cacheKey should fail");
}

- (void)testDeleteAll {
    // Create multiple test records
    NSArray<NSString *> *hostnames = @[@"host1.example.com", @"host2.example.com", @"host3.example.com"];
    NSArray<NSString *> *cacheKeys = @[@"cache_key_1", @"cache_key_2", @"cache_key_3"];

    for (NSInteger i = 0; i < hostnames.count; i++) {
        HttpdnsHostRecord *record = [self createTestRecordWithHostname:hostnames[i] cacheKey:cacheKeys[i]];
        [self.db createOrUpdate:record];
    }

    // Verify records exist
    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNotNil(fetchedRecord, @"Record should exist before deletion");
    }

    // Delete all records
    BOOL result = [self.db deleteAll];
    XCTAssertTrue(result, @"Deleting all records should succeed");

    // Verify all records were deleted
    for (NSString *cacheKey in cacheKeys) {
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNil(fetchedRecord, @"Record should be deleted");
    }
}

#pragma mark - Timestamp Tests

- (void)testCreateAtPreservation {
    // Create a test record with a specific createAt time
    NSDate *pastDate = [NSDate dateWithTimeIntervalSinceNow:-3600]; // 1 hour ago
    HttpdnsHostRecord *record = [[HttpdnsHostRecord alloc] initWithId:1
                                                             cacheKey:@"timestamp_cache_key"
                                                             hostName:@"timestamp.example.com"
                                                             createAt:pastDate
                                                             modifyAt:[NSDate date]
                                                             clientIp:@"192.168.1.1"
                                                                v4ips:@[@"192.168.1.2"]
                                                                v4ttl:300
                                                         v4LookupTime:1000
                                                                v6ips:@[]
                                                                v6ttl:0
                                                         v6LookupTime:0
                                                                extra:@""];

    // Insert the record
    BOOL result = [self.db createOrUpdate:record];
    XCTAssertTrue(result, @"Record creation should succeed");

    // Fetch the record
    HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:@"timestamp_cache_key"];
    XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the record");

    // Verify createAt was preserved
    // 新插入的记录一定会使用当前时间
    XCTAssertEqualWithAccuracy([fetchedRecord.createAt timeIntervalSince1970],
                               [[NSDate date] timeIntervalSince1970],
                              0.001,
                              @"createAt should be preserved");

    // Update the record
    HttpdnsHostRecord *updatedRecord = [[HttpdnsHostRecord alloc] initWithId:fetchedRecord.id
                                                                    cacheKey:@"timestamp_cache_key"
                                                                    hostName:@"timestamp.example.com"
                                                                    createAt:[NSDate date] // Try to change createAt
                                                                    modifyAt:[NSDate date]
                                                                    clientIp:@"10.0.0.1"
                                                                       v4ips:@[@"10.0.0.2"]
                                                                       v4ttl:600
                                                                v4LookupTime:2000
                                                                       v6ips:@[]
                                                                       v6ttl:0
                                                                v6LookupTime:0
                                                                       extra:@""];

    // Update the record
    result = [self.db createOrUpdate:updatedRecord];
    XCTAssertTrue(result, @"Record update should succeed");

    // Fetch the updated record
    HttpdnsHostRecord *updatedFetchedRecord = [self.db selectByCacheKey:@"timestamp_cache_key"];
    XCTAssertNotNil(updatedFetchedRecord, @"Should be able to fetch the updated record");

    // Verify createAt was still preserved after update
    XCTAssertEqualWithAccuracy([updatedFetchedRecord.createAt timeIntervalSince1970],
                               [fetchedRecord.createAt timeIntervalSince1970],
                              0.001,
                              @"createAt should still be preserved after update");

    // Verify modifyAt was updated
    XCTAssertTrue([updatedFetchedRecord.modifyAt timeIntervalSinceDate:fetchedRecord.modifyAt] > 0,
                 @"modifyAt should be updated to a later time");
}

#pragma mark - Concurrency Tests

- (void)testConcurrentAccess {
    // Create a dispatch group for synchronization
    dispatch_group_t group = dispatch_group_create();

    // Create a concurrent queue
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.test.concurrent", DISPATCH_QUEUE_CONCURRENT);

    // Number of concurrent operations
    NSInteger operationCount = 10;

    // Perform concurrent operations
    for (NSInteger i = 0; i < operationCount; i++) {
        dispatch_group_enter(group);
        dispatch_async(concurrentQueue, ^{
            NSString *hostname = [NSString stringWithFormat:@"concurrent%ld.example.com", (long)i];
            NSString *cacheKey = [NSString stringWithFormat:@"concurrent_cache_key_%ld", (long)i];
            HttpdnsHostRecord *record = [self createTestRecordWithHostname:hostname cacheKey:cacheKey];

            // Insert the record
            BOOL result = [self.db createOrUpdate:record];
            XCTAssertTrue(result, @"Record creation should succeed in concurrent operation");

            // Query the record
            HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
            XCTAssertNotNil(fetchedRecord, @"Should be able to fetch the record in concurrent operation");

            dispatch_group_leave(group);
        });
    }

    // Wait for all operations to complete with a timeout
    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)), 0,
                  @"All concurrent operations should complete within timeout");

    // Verify all records were created
    for (NSInteger i = 0; i < operationCount; i++) {
        NSString *cacheKey = [NSString stringWithFormat:@"concurrent_cache_key_%ld", (long)i];
        HttpdnsHostRecord *fetchedRecord = [self.db selectByCacheKey:cacheKey];
        XCTAssertNotNil(fetchedRecord, @"Should be able to fetch all records after concurrent operations");
    }
}

#pragma mark - Helper Methods

- (HttpdnsHostRecord *)createTestRecordWithHostname:(NSString *)hostname cacheKey:(NSString *)cacheKey {
    return [[HttpdnsHostRecord alloc] initWithId:1
                                        cacheKey:cacheKey
                                        hostName:hostname
                                        createAt:[NSDate date]
                                        modifyAt:[NSDate date]
                                        clientIp:@"192.168.1.1"
                                           v4ips:@[@"192.168.1.2", @"192.168.1.3"]
                                           v4ttl:300
                                    v4LookupTime:1000
                                           v6ips:@[@"2001:db8::1"]
                                           v6ttl:600
                                    v6LookupTime:2000
                                           extra:@"value"];
}

@end
