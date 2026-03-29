/*
 * OCStore.m
 * ClawPod - SQLite Storage Implementation
 *
 * WAL mode for concurrent reads, prepared statement caching,
 * auto-vacuum. All ops on serial queue for thread safety.
 */

#import "Store.h"

NSString *const OCStoreErrorDomain = @"OCStoreError";

#pragma mark - OCStoreRow

@interface OCStoreRow () {
    sqlite3_stmt *_stmt;
    NSDictionary *_columnMap;  /* column name -> index */
}
- (instancetype)initWithStatement:(sqlite3_stmt *)stmt columnMap:(NSDictionary *)map;
@end

@implementation OCStoreRow

- (instancetype)initWithStatement:(sqlite3_stmt *)stmt columnMap:(NSDictionary *)map {
    if ((self = [super init])) {
        _stmt = stmt;
        _columnMap = [map retain];
    }
    return self;
}

- (void)dealloc {
    [_columnMap release];
    [super dealloc];
}

- (int)_indexForColumn:(NSString *)column {
    NSNumber *idx = [_columnMap objectForKey:column];
    return idx ? [idx intValue] : -1;
}

- (NSString *)stringForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return nil;
    const unsigned char *text = sqlite3_column_text(_stmt, idx);
    if (!text) return nil;
    return [NSString stringWithUTF8String:(const char *)text];
}

- (NSInteger)integerForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return 0;
    return (NSInteger)sqlite3_column_int(_stmt, idx);
}

- (int64_t)int64ForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return 0;
    return sqlite3_column_int64(_stmt, idx);
}

- (double)doubleForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return 0.0;
    return sqlite3_column_double(_stmt, idx);
}

- (NSData *)dataForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return nil;
    const void *blob = sqlite3_column_blob(_stmt, idx);
    int len = sqlite3_column_bytes(_stmt, idx);
    if (!blob || len <= 0) return nil;
    return [NSData dataWithBytes:blob length:len];
}

- (BOOL)boolForColumn:(NSString *)column {
    return [self integerForColumn:column] != 0;
}

- (BOOL)isNullForColumn:(NSString *)column {
    int idx = [self _indexForColumn:column];
    if (idx < 0) return YES;
    return sqlite3_column_type(_stmt, idx) == SQLITE_NULL;
}

@end

#pragma mark - OCStore

@interface OCStore () {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSMutableDictionary *_stmtCache;  /* SQL -> sqlite3_stmt* wrapped in NSValue */
}
@end

@implementation OCStore

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _databasePath = [path copy];
        _statementCacheLimit = 32;
        _queue = dispatch_queue_create("pro.matthesketh.legacypodclaw.store", DISPATCH_QUEUE_SERIAL);
        _stmtCache = [[NSMutableDictionary alloc] initWithCapacity:32];
    }
    return self;
}

- (void)dealloc {
    [self close];
    [_databasePath release];
    [_stmtCache release];
    [_queue release];
    [super dealloc];
}

- (BOOL)open:(NSError **)error {
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        int rc = sqlite3_open([_databasePath UTF8String], &_db);
        if (rc != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:OCStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            }
            return;
        }

        /* Configure for low-memory device */
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA auto_vacuum=INCREMENTAL", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA cache_size=-2000", NULL, NULL, NULL);  /* 2MB cache */
        sqlite3_exec(_db, "PRAGMA temp_store=MEMORY", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA mmap_size=4194304", NULL, NULL, NULL);  /* 4MB mmap */

        _isOpen = YES;
        success = YES;
    });
    return success;
}

- (void)close {
    dispatch_sync(_queue, ^{
        if (!_db) return;

        /* Finalize all cached statements */
        for (NSValue *val in [_stmtCache allValues]) {
            sqlite3_stmt *stmt = [val pointerValue];
            sqlite3_finalize(stmt);
        }
        [_stmtCache removeAllObjects];

        sqlite3_close(_db);
        _db = NULL;
        _isOpen = NO;
    });
}

#pragma mark - Statement Cache

- (sqlite3_stmt *)_cachedStatementForSQL:(NSString *)sql error:(NSError **)error {
    NSValue *cached = [_stmtCache objectForKey:sql];
    if (cached) {
        sqlite3_stmt *stmt = [cached pointerValue];
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
        return stmt;
    }

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:OCStoreErrorDomain
                                         code:rc
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
        }
        return NULL;
    }

    /* Evict oldest if cache full */
    if ([_stmtCache count] >= _statementCacheLimit) {
        NSString *firstKey = [[_stmtCache allKeys] objectAtIndex:0];
        sqlite3_stmt *old = [[_stmtCache objectForKey:firstKey] pointerValue];
        sqlite3_finalize(old);
        [_stmtCache removeObjectForKey:firstKey];
    }

    [_stmtCache setObject:[NSValue valueWithPointer:stmt] forKey:sql];
    return stmt;
}

- (void)_bindParams:(NSArray *)params toStatement:(sqlite3_stmt *)stmt {
    if (!params) return;

    for (NSUInteger i = 0; i < [params count]; i++) {
        id param = [params objectAtIndex:i];
        int idx = (int)(i + 1);

        if ([param isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(stmt, idx, [param UTF8String], -1, SQLITE_TRANSIENT);
        } else if ([param isKindOfClass:[NSNumber class]]) {
            const char *type = [param objCType];
            if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
                sqlite3_bind_double(stmt, idx, [param doubleValue]);
            } else if (strcmp(type, @encode(long long)) == 0 ||
                       strcmp(type, @encode(unsigned long long)) == 0) {
                sqlite3_bind_int64(stmt, idx, [param longLongValue]);
            } else {
                sqlite3_bind_int(stmt, idx, [param intValue]);
            }
        } else if ([param isKindOfClass:[NSData class]]) {
            sqlite3_bind_blob(stmt, idx, [param bytes], (int)[param length], SQLITE_TRANSIENT);
        } else if ([param isKindOfClass:[NSNull class]]) {
            sqlite3_bind_null(stmt, idx);
        }
    }
}

#pragma mark - Execute

- (BOOL)execute:(NSString *)sql error:(NSError **)error {
    return [self execute:sql params:nil error:error];
}

- (BOOL)execute:(NSString *)sql params:(NSArray *)params error:(NSError **)error {
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *stmt = [self _cachedStatementForSQL:sql error:error];
        if (!stmt) return;

        [self _bindParams:params toStatement:stmt];

        int rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
            if (error) {
                *error = [NSError errorWithDomain:OCStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            }
            return;
        }
        success = YES;
    });
    return success;
}

#pragma mark - Query

- (NSDictionary *)_columnMapForStatement:(sqlite3_stmt *)stmt {
    int colCount = sqlite3_column_count(stmt);
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:colCount];
    for (int i = 0; i < colCount; i++) {
        const char *name = sqlite3_column_name(stmt, i);
        [map setObject:@(i) forKey:[NSString stringWithUTF8String:name]];
    }
    return map;
}

- (BOOL)query:(NSString *)sql
       params:(NSArray *)params
    enumerate:(OCStoreRowBlock)block
        error:(NSError **)error {
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *stmt = [self _cachedStatementForSQL:sql error:error];
        if (!stmt) return;

        [self _bindParams:params toStatement:stmt];

        NSDictionary *colMap = [self _columnMapForStatement:stmt];
        OCStoreRow *row = [[[OCStoreRow alloc] initWithStatement:stmt columnMap:colMap] autorelease];

        BOOL stop = NO;
        int rc;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW && !stop) {
            block(row, &stop);
        }

        if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
            if (error) {
                *error = [NSError errorWithDomain:OCStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            }
            return;
        }
        success = YES;
    });
    return success;
}

- (NSArray *)queryAll:(NSString *)sql params:(NSArray *)params error:(NSError **)error {
    NSMutableArray *results = [NSMutableArray array];
    __block NSDictionary *colMap = nil;

    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *stmt = [self _cachedStatementForSQL:sql error:error];
        if (!stmt) return;

        [self _bindParams:params toStatement:stmt];
        colMap = [self _columnMapForStatement:stmt];

        int rc;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[colMap count]];
            for (NSString *col in colMap) {
                int idx = [[colMap objectForKey:col] intValue];
                int type = sqlite3_column_type(stmt, idx);

                switch (type) {
                    case SQLITE_TEXT: {
                        const unsigned char *text = sqlite3_column_text(stmt, idx);
                        if (text) [dict setObject:[NSString stringWithUTF8String:(const char *)text]
                                           forKey:col];
                        break;
                    }
                    case SQLITE_INTEGER:
                        [dict setObject:@(sqlite3_column_int64(stmt, idx)) forKey:col];
                        break;
                    case SQLITE_FLOAT:
                        [dict setObject:@(sqlite3_column_double(stmt, idx)) forKey:col];
                        break;
                    case SQLITE_BLOB: {
                        const void *blob = sqlite3_column_blob(stmt, idx);
                        int len = sqlite3_column_bytes(stmt, idx);
                        if (blob && len > 0) {
                            [dict setObject:[NSData dataWithBytes:blob length:len] forKey:col];
                        }
                        break;
                    }
                    case SQLITE_NULL:
                    default:
                        [dict setObject:[NSNull null] forKey:col];
                        break;
                }
            }
            [results addObject:dict];
        }

        if (rc != SQLITE_DONE) {
            if (error) {
                *error = [NSError errorWithDomain:OCStoreErrorDomain
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            }
            return;
        }
        success = YES;
    });

    return success ? results : nil;
}

- (NSInteger)queryInteger:(NSString *)sql params:(NSArray *)params {
    __block NSInteger result = 0;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *stmt = [self _cachedStatementForSQL:sql error:NULL];
        if (!stmt) return;
        [self _bindParams:params toStatement:stmt];
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = (NSInteger)sqlite3_column_int64(stmt, 0);
        }
    });
    return result;
}

- (NSString *)queryString:(NSString *)sql params:(NSArray *)params {
    __block NSString *result = nil;
    dispatch_sync(_queue, ^{
        sqlite3_stmt *stmt = [self _cachedStatementForSQL:sql error:NULL];
        if (!stmt) return;
        [self _bindParams:params toStatement:stmt];
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(stmt, 0);
            if (text) result = [[NSString stringWithUTF8String:(const char *)text] retain];
        }
    });
    return [result autorelease];
}

#pragma mark - Transactions

- (BOOL)beginTransaction:(NSError **)error {
    return [self execute:@"BEGIN TRANSACTION" error:error];
}

- (BOOL)commitTransaction:(NSError **)error {
    return [self execute:@"COMMIT" error:error];
}

- (BOOL)rollbackTransaction:(NSError **)error {
    return [self execute:@"ROLLBACK" error:error];
}

- (BOOL)inTransaction:(BOOL(^)(void))block error:(NSError **)error {
    if (![self beginTransaction:error]) return NO;

    BOOL success = block();
    if (success) {
        return [self commitTransaction:error];
    } else {
        [self rollbackTransaction:NULL];
        return NO;
    }
}

- (int64_t)lastInsertRowId {
    __block int64_t rowId = 0;
    dispatch_sync(_queue, ^{
        if (_db) rowId = sqlite3_last_insert_rowid(_db);
    });
    return rowId;
}

- (NSInteger)changesCount {
    __block NSInteger changes = 0;
    dispatch_sync(_queue, ^{
        if (_db) changes = sqlite3_changes(_db);
    });
    return changes;
}

- (void)vacuum {
    dispatch_async(_queue, ^{
        if (_db) sqlite3_exec(_db, "PRAGMA incremental_vacuum(100)", NULL, NULL, NULL);
    });
}

- (void)optimize {
    dispatch_async(_queue, ^{
        if (_db) sqlite3_exec(_db, "PRAGMA optimize", NULL, NULL, NULL);
    });
}

- (int64_t)databaseSize {
    __block int64_t size = 0;
    dispatch_sync(_queue, ^{
        if (_db) {
            sqlite3_stmt *stmt;
            if (sqlite3_prepare_v2(_db, "PRAGMA page_count", -1, &stmt, NULL) == SQLITE_OK) {
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    int64_t pages = sqlite3_column_int64(stmt, 0);
                    sqlite3_finalize(stmt);
                    if (sqlite3_prepare_v2(_db, "PRAGMA page_size", -1, &stmt, NULL) == SQLITE_OK) {
                        if (sqlite3_step(stmt) == SQLITE_ROW) {
                            int64_t pageSize = sqlite3_column_int64(stmt, 0);
                            size = pages * pageSize;
                        }
                    }
                }
                sqlite3_finalize(stmt);
            }
        }
    });
    return size;
}

@end

#pragma mark - OCKeyValueStore

@interface OCKeyValueStore () {
    OCStore *_store;
    NSString *_tableName;
}
@end

@implementation OCKeyValueStore

- (instancetype)initWithStore:(OCStore *)store tableName:(NSString *)tableName {
    if ((self = [super init])) {
        _store = [store retain];
        _tableName = [tableName copy];
    }
    return self;
}

- (void)dealloc {
    [_store release];
    [_tableName release];
    [super dealloc];
}

- (BOOL)setup:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:
        @"CREATE TABLE IF NOT EXISTS %@ ("
        @"  key TEXT PRIMARY KEY NOT NULL,"
        @"  value BLOB,"
        @"  updated_at INTEGER DEFAULT (strftime('%%s','now'))"
        @")", _tableName];
    return [_store execute:sql error:error];
}

- (NSString *)stringForKey:(NSString *)key {
    NSString *sql = [NSString stringWithFormat:
        @"SELECT value FROM %@ WHERE key = ?", _tableName];
    return [_store queryString:sql params:@[key]];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    NSString *sql = [NSString stringWithFormat:
        @"INSERT OR REPLACE INTO %@ (key, value, updated_at) "
        @"VALUES (?, ?, strftime('%%s','now'))", _tableName];
    [_store execute:sql params:@[key, value ?: [NSNull null]] error:NULL];
}

- (NSInteger)integerForKey:(NSString *)key {
    NSString *sql = [NSString stringWithFormat:
        @"SELECT value FROM %@ WHERE key = ?", _tableName];
    return [_store queryInteger:sql params:@[key]];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [self setString:[@(value) stringValue] forKey:key];
}

- (NSData *)dataForKey:(NSString *)key {
    __block NSData *result = nil;
    NSString *sql = [NSString stringWithFormat:
        @"SELECT value FROM %@ WHERE key = ?", _tableName];
    [_store query:sql params:@[key] enumerate:^(OCStoreRow *row, BOOL *stop) {
        result = [[row dataForColumn:@"value"] retain];
        *stop = YES;
    } error:NULL];
    return [result autorelease];
}

- (void)setData:(NSData *)value forKey:(NSString *)key {
    NSString *sql = [NSString stringWithFormat:
        @"INSERT OR REPLACE INTO %@ (key, value, updated_at) "
        @"VALUES (?, ?, strftime('%%s','now'))", _tableName];
    [_store execute:sql params:@[key, value ?: [NSNull null]] error:NULL];
}

- (void)removeKey:(NSString *)key {
    NSString *sql = [NSString stringWithFormat:
        @"DELETE FROM %@ WHERE key = ?", _tableName];
    [_store execute:sql params:@[key] error:NULL];
}

- (NSDictionary *)allEntries {
    NSString *sql = [NSString stringWithFormat:
        @"SELECT key, value FROM %@", _tableName];
    NSArray *rows = [_store queryAll:sql params:nil error:NULL];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[rows count]];
    for (NSDictionary *row in rows) {
        id key = [row objectForKey:@"key"];
        id value = [row objectForKey:@"value"];
        if (key && value) [dict setObject:value forKey:key];
    }
    return dict;
}

@end
