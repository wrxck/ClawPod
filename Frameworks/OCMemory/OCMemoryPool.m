/*
 * OCMemoryPool.m
 * ClawPod - Memory Management Implementation
 *
 * Critical for 256MB iPod Touch 4th gen. Provides:
 * - Buffer pooling to reduce malloc/free overhead
 * - LRU cache with byte budgets
 * - Memory pressure monitoring via mach_task_info
 */

#import "OCMemoryPool.h"
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <libkern/OSAtomic.h>

NSString *const OCMemoryPressureChangedNotification = @"OCMemoryPressureChanged";
NSString *const OCMemoryPressureLevelKey = @"pressure";

static const NSUInteger kDefaultAppBudget = 80 * 1024 * 1024;  /* 80MB for 256MB device */
static const NSTimeInterval kDefaultPollInterval = 5.0;

#pragma mark - OCBufferPool

@interface OCBufferPool () {
    NSMutableArray *_pool;
    NSUInteger _inUse;
    OSSpinLock _lock;
}
@end

@implementation OCBufferPool

- (instancetype)initWithBufferSize:(NSUInteger)size capacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _bufferSize = size;
        _poolCapacity = capacity;
        _inUse = 0;
        _lock = OS_SPINLOCK_INIT;
        _pool = [[NSMutableArray alloc] initWithCapacity:capacity];

        /* Pre-allocate half the pool to amortize startup cost */
        NSUInteger prealloc = capacity / 2;
        for (NSUInteger i = 0; i < prealloc; i++) {
            NSMutableData *buf = [[NSMutableData alloc] initWithLength:size];
            [_pool addObject:buf];
            [buf release];
        }
    }
    return self;
}

- (void)dealloc {
    [_pool release];
    [super dealloc];
}

- (NSMutableData *)checkoutBuffer {
    OSSpinLockLock(&_lock);
    NSMutableData *buffer = nil;

    if ([_pool count] > 0) {
        buffer = [[_pool lastObject] retain];
        [_pool removeLastObject];
    }
    _inUse++;
    OSSpinLockUnlock(&_lock);

    if (!buffer) {
        buffer = [[NSMutableData alloc] initWithLength:_bufferSize];
    }

    [buffer setLength:_bufferSize];
    return [buffer autorelease];
}

- (void)returnBuffer:(NSMutableData *)buffer {
    if (!buffer) return;

    OSSpinLockLock(&_lock);
    _inUse--;
    if ([_pool count] < _poolCapacity) {
        [_pool addObject:buffer];
    }
    /* else: buffer is released, pool is full */
    OSSpinLockUnlock(&_lock);
}

- (NSUInteger)buffersInUse {
    return _inUse;
}

- (void)drain {
    OSSpinLockLock(&_lock);
    [_pool removeAllObjects];
    OSSpinLockUnlock(&_lock);
}

@end

#pragma mark - LRU Cache Node

@interface _OCLRUNode : NSObject {
    @public
    id<NSCopying> key;
    id value;
    NSUInteger cost;
    _OCLRUNode *prev;
    _OCLRUNode *next;
}
@end

@implementation _OCLRUNode
- (void)dealloc {
    [(id)key release];
    [value release];
    [super dealloc];
}
@end

#pragma mark - OCLRUCache

@interface OCLRUCache () {
    NSMutableDictionary *_map;
    _OCLRUNode *_head;
    _OCLRUNode *_tail;
    OSSpinLock _lock;
}
@end

@implementation OCLRUCache

- (instancetype)initWithCountLimit:(NSUInteger)countLimit
                        byteBudget:(NSUInteger)byteBudget {
    if ((self = [super init])) {
        _countLimit = countLimit;
        _byteBudget = byteBudget;
        _currentCount = 0;
        _currentBytes = 0;
        _map = [[NSMutableDictionary alloc] initWithCapacity:countLimit];
        _head = nil;
        _tail = nil;
        _lock = OS_SPINLOCK_INIT;
    }
    return self;
}

- (void)dealloc {
    [self removeAllObjects];
    [_map release];
    [super dealloc];
}

- (void)_moveToHead:(_OCLRUNode *)node {
    if (node == _head) return;

    /* Remove from current position */
    if (node->prev) node->prev->next = node->next;
    if (node->next) node->next->prev = node->prev;
    if (node == _tail) _tail = node->prev;

    /* Insert at head */
    node->prev = nil;
    node->next = _head;
    if (_head) _head->prev = node;
    _head = node;
    if (!_tail) _tail = node;
}

- (void)_removeTail {
    if (!_tail) return;

    _OCLRUNode *old = _tail;
    [_map removeObjectForKey:old->key];
    _currentBytes -= old->cost;
    _currentCount--;

    _tail = old->prev;
    if (_tail) {
        _tail->next = nil;
    } else {
        _head = nil;
    }
    [old release];
}

- (id)objectForKey:(id<NSCopying>)key {
    OSSpinLockLock(&_lock);
    _OCLRUNode *node = [_map objectForKey:key];
    if (node) {
        [self _moveToHead:node];
        id val = [[node->value retain] autorelease];
        OSSpinLockUnlock(&_lock);
        return val;
    }
    OSSpinLockUnlock(&_lock);
    return nil;
}

- (void)setObject:(id)obj forKey:(id<NSCopying>)key cost:(NSUInteger)cost {
    OSSpinLockLock(&_lock);

    _OCLRUNode *existing = [_map objectForKey:key];
    if (existing) {
        _currentBytes -= existing->cost;
        [existing->value release];
        existing->value = [obj retain];
        existing->cost = cost;
        _currentBytes += cost;
        [self _moveToHead:existing];
    } else {
        _OCLRUNode *node = [[_OCLRUNode alloc] init];
        node->key = [key copyWithZone:nil];
        node->value = [obj retain];
        node->cost = cost;
        node->prev = nil;
        node->next = _head;
        if (_head) _head->prev = node;
        _head = node;
        if (!_tail) _tail = node;

        [_map setObject:node forKey:key];
        _currentCount++;
        _currentBytes += cost;
        /* node retained by map, we don't release here */
    }

    /* Evict if over limits */
    while (_currentCount > _countLimit || _currentBytes > _byteBudget) {
        if (!_tail) break;
        [self _removeTail];
    }

    OSSpinLockUnlock(&_lock);
}

- (void)removeObjectForKey:(id<NSCopying>)key {
    OSSpinLockLock(&_lock);
    _OCLRUNode *node = [_map objectForKey:key];
    if (node) {
        if (node->prev) node->prev->next = node->next;
        if (node->next) node->next->prev = node->prev;
        if (node == _head) _head = node->next;
        if (node == _tail) _tail = node->prev;
        _currentBytes -= node->cost;
        _currentCount--;
        [_map removeObjectForKey:key];
        [node release];
    }
    OSSpinLockUnlock(&_lock);
}

- (void)removeAllObjects {
    OSSpinLockLock(&_lock);
    [_map removeAllObjects];
    /* Release linked list */
    _OCLRUNode *curr = _head;
    while (curr) {
        _OCLRUNode *next = curr->next;
        [curr release];
        curr = next;
    }
    _head = nil;
    _tail = nil;
    _currentCount = 0;
    _currentBytes = 0;
    OSSpinLockUnlock(&_lock);
}

- (void)trimToBytes:(NSUInteger)targetBytes {
    OSSpinLockLock(&_lock);
    while (_currentBytes > targetBytes && _tail) {
        [self _removeTail];
    }
    OSSpinLockUnlock(&_lock);
}

@end

#pragma mark - OCMemoryMonitor

@interface OCMemoryMonitor () {
    NSTimer *_pollTimer;
    NSMutableDictionary *_handlers;
    NSUInteger _nextToken;
    OCMemoryPressure _lastPressure;
    NSUInteger _freeMemoryBytes;
    NSUInteger _usedMemoryBytes;
    NSUInteger _appMemoryBytes;
}
@end

@implementation OCMemoryMonitor

+ (instancetype)sharedMonitor {
    static OCMemoryMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OCMemoryMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _appMemoryBudget = kDefaultAppBudget;
        _pollInterval = kDefaultPollInterval;
        _handlers = [[NSMutableDictionary alloc] init];
        _nextToken = 0;
        _lastPressure = OCMemoryPressureNormal;
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
    [_handlers release];
    [super dealloc];
}

- (void)startMonitoring {
    if (_pollTimer) return;

    [self checkNow];

    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:_pollInterval
                                                 target:self
                                               selector:@selector(_poll)
                                               userInfo:nil
                                                repeats:YES];
}

- (void)stopMonitoring {
    [_pollTimer invalidate];
    _pollTimer = nil;
}

- (void)_poll {
    [self checkNow];
}

- (void)checkNow {
    /* Get app memory usage via mach task info */
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(),
                                 MACH_TASK_BASIC_INFO,
                                 (task_info_t)&info,
                                 &count);

    if (kr == KERN_SUCCESS) {
        _appMemoryBytes = info.resident_size;
    }

    /* Get system memory stats */
    vm_statistics_data_t vmStats;
    mach_msg_type_number_t vmCount = HOST_VM_INFO_COUNT;
    host_statistics(mach_host_self(), HOST_VM_INFO,
                    (host_info_t)&vmStats, &vmCount);

    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);

    _freeMemoryBytes = vmStats.free_count * pageSize;
    _usedMemoryBytes = (vmStats.active_count + vmStats.inactive_count +
                        vmStats.wire_count) * pageSize;

    /* Calculate pressure based on our app budget */
    OCMemoryPressure pressure;
    float ratio = (float)_appMemoryBytes / (float)_appMemoryBudget;

    if (ratio > 0.9f) {
        pressure = OCMemoryPressureTerminal;
    } else if (ratio > 0.8f) {
        pressure = OCMemoryPressureCritical;
    } else if (ratio > 0.6f) {
        pressure = OCMemoryPressureWarning;
    } else {
        pressure = OCMemoryPressureNormal;
    }

    _currentPressure = pressure;

    if (pressure != _lastPressure) {
        _lastPressure = pressure;

        /* Post notification */
        [[NSNotificationCenter defaultCenter]
         postNotificationName:OCMemoryPressureChangedNotification
         object:self
         userInfo:@{OCMemoryPressureLevelKey: @(pressure)}];

        /* Call registered handlers */
        for (NSNumber *token in [_handlers allKeys]) {
            void(^handler)(OCMemoryPressure) = [_handlers objectForKey:token];
            handler(pressure);
        }
    }
}

- (id)addPressureHandler:(void(^)(OCMemoryPressure))handler {
    NSNumber *token = @(_nextToken++);
    [_handlers setObject:[[handler copy] autorelease] forKey:token];
    return token;
}

- (void)removePressureHandler:(id)token {
    [_handlers removeObjectForKey:token];
}

- (NSUInteger)freeMemoryBytes {
    return _freeMemoryBytes;
}

- (NSUInteger)usedMemoryBytes {
    return _usedMemoryBytes;
}

- (NSUInteger)appMemoryBytes {
    return _appMemoryBytes;
}

@end
