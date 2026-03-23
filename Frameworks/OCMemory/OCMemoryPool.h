/*
 * OCMemoryPool.h
 * ClawPod - Memory Management Framework
 *
 * Provides memory pressure monitoring, pooled buffer allocation,
 * and LRU caches with hard caps for the 256MB iPod Touch 4th gen.
 */

#import <Foundation/Foundation.h>

#pragma mark - Memory Pressure

typedef NS_ENUM(NSUInteger, OCMemoryPressure) {
    OCMemoryPressureNormal   = 0,  // < 60% used
    OCMemoryPressureWarning  = 1,  // 60-80% used
    OCMemoryPressureCritical = 2,  // > 80% used
    OCMemoryPressureTerminal = 3   // > 90% used - shed everything
};

extern NSString *const OCMemoryPressureChangedNotification;
extern NSString *const OCMemoryPressureLevelKey;

#pragma mark - Buffer Pool

/*
 * OCBufferPool - Reusable byte buffer pool to avoid malloc/free churn.
 * Pre-allocates a fixed number of buffers at a given size.
 * Thread-safe via OSAtomicQueue.
 */
@interface OCBufferPool : NSObject

@property (nonatomic, readonly) NSUInteger bufferSize;
@property (nonatomic, readonly) NSUInteger poolCapacity;
@property (nonatomic, readonly) NSUInteger buffersInUse;

- (instancetype)initWithBufferSize:(NSUInteger)size capacity:(NSUInteger)capacity;

/* Returns a pooled NSMutableData or creates a new one if pool exhausted. */
- (NSMutableData *)checkoutBuffer;

/* Returns a buffer to the pool. Data content is NOT cleared for performance. */
- (void)returnBuffer:(NSMutableData *)buffer;

/* Drain all pooled buffers to free memory. */
- (void)drain;

@end

#pragma mark - LRU Cache

/*
 * OCLRUCache - Fixed-capacity key-value cache with LRU eviction.
 * Tracks approximate byte cost of entries. Evicts when count OR
 * byte budget is exceeded. Thread-safe.
 */
@interface OCLRUCache : NSObject

@property (nonatomic, readonly) NSUInteger countLimit;
@property (nonatomic, readonly) NSUInteger byteBudget;
@property (nonatomic, readonly) NSUInteger currentCount;
@property (nonatomic, readonly) NSUInteger currentBytes;

- (instancetype)initWithCountLimit:(NSUInteger)countLimit
                        byteBudget:(NSUInteger)byteBudget;

- (id)objectForKey:(id<NSCopying>)key;
- (void)setObject:(id)obj forKey:(id<NSCopying>)key cost:(NSUInteger)cost;
- (void)removeObjectForKey:(id<NSCopying>)key;
- (void)removeAllObjects;

/* Evict entries until under the given byte target. */
- (void)trimToBytes:(NSUInteger)targetBytes;

@end

#pragma mark - Memory Monitor

/*
 * OCMemoryMonitor - Singleton that polls device memory usage
 * and posts notifications on pressure transitions.
 * On iPod Touch 4 (256MB), we budget ~80MB for ClawPod.
 */
@interface OCMemoryMonitor : NSObject

@property (nonatomic, readonly) OCMemoryPressure currentPressure;
@property (nonatomic, readonly) NSUInteger freeMemoryBytes;
@property (nonatomic, readonly) NSUInteger usedMemoryBytes;
@property (nonatomic, readonly) NSUInteger appMemoryBytes;

/* Our hard budget in bytes. Default 80MB for 256MB device. */
@property (nonatomic, assign) NSUInteger appMemoryBudget;

/* Polling interval in seconds. Default 5s. */
@property (nonatomic, assign) NSTimeInterval pollInterval;

+ (instancetype)sharedMonitor;

- (void)startMonitoring;
- (void)stopMonitoring;

/* Force an immediate memory check and pressure notification if changed. */
- (void)checkNow;

/* Register a block to be called on pressure change. Returns token for removal. */
- (id)addPressureHandler:(void(^)(OCMemoryPressure pressure))handler;
- (void)removePressureHandler:(id)token;

@end
