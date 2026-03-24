/*
 * OCStore.h
 * ClawPod - Lightweight SQLite Storage Framework
 *
 * Thin wrapper over sqlite3 with prepared statement caching,
 * WAL mode for concurrent reads, and auto-vacuum.
 * All operations are synchronous on a serial dispatch queue.
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>

extern NSString *const OCStoreErrorDomain;

#pragma mark - OCStoreRow

/* Lightweight row accessor - avoids creating dictionaries per row. */
@interface OCStoreRow : NSObject

- (NSString *)stringForColumn:(NSString *)column;
- (NSInteger)integerForColumn:(NSString *)column;
- (int64_t)int64ForColumn:(NSString *)column;
- (double)doubleForColumn:(NSString *)column;
- (NSData *)dataForColumn:(NSString *)column;
- (BOOL)boolForColumn:(NSString *)column;
- (BOOL)isNullForColumn:(NSString *)column;

@end

#pragma mark - OCStore

typedef void(^OCStoreRowBlock)(OCStoreRow *row, BOOL *stop);
typedef void(^OCStoreCompletionBlock)(BOOL success, NSError *error);

@interface OCStore : NSObject

@property (nonatomic, readonly) NSString *databasePath;
@property (nonatomic, readonly) BOOL isOpen;

/* Maximum number of cached prepared statements. Default 32. */
@property (nonatomic, assign) NSUInteger statementCacheLimit;

- (instancetype)initWithPath:(NSString *)path;

- (BOOL)open:(NSError **)error;
- (void)close;

/* Execute SQL with no results (INSERT, UPDATE, DELETE, CREATE). */
- (BOOL)execute:(NSString *)sql error:(NSError **)error;
- (BOOL)execute:(NSString *)sql params:(NSArray *)params error:(NSError **)error;

/* Query with row-by-row enumeration to avoid loading all rows into memory. */
- (BOOL)query:(NSString *)sql
       params:(NSArray *)params
     enumerate:(OCStoreRowBlock)block
        error:(NSError **)error;

/* Convenience: query returning array of dictionaries (use sparingly). */
- (NSArray *)queryAll:(NSString *)sql params:(NSArray *)params error:(NSError **)error;

/* Single-value queries. */
- (NSInteger)queryInteger:(NSString *)sql params:(NSArray *)params;
- (NSString *)queryString:(NSString *)sql params:(NSArray *)params;

/* Transaction support. */
- (BOOL)beginTransaction:(NSError **)error;
- (BOOL)commitTransaction:(NSError **)error;
- (BOOL)rollbackTransaction:(NSError **)error;
- (BOOL)inTransaction:(BOOL(^)(void))block error:(NSError **)error;

/* Last insert rowid. */
- (int64_t)lastInsertRowId;

/* Number of rows changed by last statement. */
- (NSInteger)changesCount;

/* Vacuum and optimize. */
- (void)vacuum;
- (void)optimize;

/* Database size in bytes. */
- (int64_t)databaseSize;

@end

#pragma mark - OCKeyValueStore

/* Simple key-value store backed by OCStore for settings/credentials. */
@interface OCKeyValueStore : NSObject

- (instancetype)initWithStore:(OCStore *)store tableName:(NSString *)tableName;
- (BOOL)setup:(NSError **)error;

- (NSString *)stringForKey:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key;

- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;

- (NSData *)dataForKey:(NSString *)key;
- (void)setData:(NSData *)value forKey:(NSString *)key;

- (void)removeKey:(NSString *)key;
- (NSDictionary *)allEntries;

@end
