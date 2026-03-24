/*
 * OCSystem.m
 * ClawPod - Deep System Integration Implementation
 */

#import "System.h"
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <IOKit/IOKitLib.h>
#import <AudioToolbox/AudioToolbox.h>

#pragma mark - CPDistributedMessagingCenter Forward Declaration

/* CPDistributedMessagingCenter loaded dynamically at runtime to avoid link errors */

#pragma mark - Daemon IPC Client

@interface CPDaemonClient () {
    id _center; /* CPDistributedMessagingCenter, loaded at runtime */
}
@end

@implementation CPDaemonClient

+ (instancetype)shared {
    static CPDaemonClient *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        /* Load AppSupport framework at runtime */
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        Class CPDMCClass = NSClassFromString(@"CPDistributedMessagingCenter");
        if (CPDMCClass) {
            _center = [[CPDMCClass performSelector:@selector(centerNamed:)
                                        withObject:@"ai.openclaw.clawpodd"] retain];
        }
    }
    return self;
}

- (void)dealloc { [_center release]; [super dealloc]; }

/* Helper to call sendMessageAndReceiveReplyName:userInfo: dynamically */
- (NSDictionary *)_sendAndReceive:(NSString *)name info:(NSDictionary *)info {
    if (!_center) return @{@"error": @"No IPC center"};
    SEL sel = @selector(sendMessageAndReceiveReplyName:userInfo:);
    if (![_center respondsToSelector:sel]) return @{@"error": @"IPC not available"};

    /* Use NSInvocation for two-arg selector */
    NSMethodSignature *sig = [_center methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:_center];
    [inv setSelector:sel];
    [inv setArgument:&name atIndex:2];
    [inv setArgument:&info atIndex:3];
    [inv invoke];
    NSDictionary *result = nil;
    [inv getReturnValue:&result];
    return result;
}

- (BOOL)isDaemonRunning {
    @try {
        NSDictionary *reply = [self _sendAndReceive:@"ping" info:@{}];
        return [[reply objectForKey:@"pong"] boolValue];
    } @catch (NSException *e) { return NO; }
}

- (NSDictionary *)batteryInfo {
    @try { return [self _sendAndReceive:@"battery" info:@{}]; }
    @catch (NSException *e) { return @{}; }
}

- (NSArray *)processList {
    @try {
        NSDictionary *reply = [self _sendAndReceive:@"processes" info:@{}];
        return [reply objectForKey:@"processes"] ?: @[];
    } @catch (NSException *e) { return @[]; }
}

- (NSDictionary *)daemonStatus {
    @try { return [self _sendAndReceive:@"status" info:@{}]; }
    @catch (NSException *e) { return @{@"running": @NO}; }
}

- (NSString *)sysctl:(NSString *)key {
    @try {
        NSDictionary *reply = [self _sendAndReceive:@"sysctl" info:@{@"key": key}];
        return [reply objectForKey:@"value"] ?: @"";
    } @catch (NSException *e) { return @""; }
}

- (NSString *)readFile:(NSString *)path {
    @try {
        NSDictionary *reply = [self _sendAndReceive:@"readFile" info:@{@"path": path}];
        return [reply objectForKey:@"content"] ?: [reply objectForKey:@"error"] ?: @"";
    } @catch (NSException *e) { return @"IPC failed"; }
}

- (NSDictionary *)readAppSandbox:(NSString *)appBundleId path:(NSString *)relativePath {
    @try {
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:appBundleId forKey:@"appId"];
        if (relativePath) [info setObject:relativePath forKey:@"path"];
        return [self _sendAndReceive:@"sandboxRead" info:info];
    } @catch (NSException *e) { return @{@"error": @"IPC failed"}; }
}

- (NSArray *)recentCrashes {
    @try {
        NSDictionary *reply = [self _sendAndReceive:@"crashes" info:@{}];
        return [reply objectForKey:@"crashes"] ?: @[];
    } @catch (NSException *e) { return @[]; }
}

- (NSDictionary *)executeAsRoot:(NSString *)command {
    @try {
        return [self _sendAndReceive:@"execute" info:@{@"command": command}];
    } @catch (NSException *e) { return @{@"error": @"IPC failed"}; }
}

@end

#pragma mark - IOKit Hardware

@implementation CPHardware

+ (NSInteger)batteryPercent {
    NSDictionary *info = [[CPDaemonClient shared] batteryInfo];
    return [[info objectForKey:@"percent"] integerValue];
}

+ (BOOL)isCharging {
    return [[[CPDaemonClient shared] batteryInfo][@"charging"] boolValue];
}

+ (NSString *)powerSource {
    return [[CPDaemonClient shared] batteryInfo][@"powerSource"] ?: @"Unknown";
}

+ (NSString *)serialNumber {
    return [[CPDaemonClient shared] sysctl:@"hw.serialnumber"] ?: @"";
}

+ (NSString *)hardwareModel {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *model = [NSString stringWithUTF8String:machine];
    free(machine);
    return model;
}

+ (NSString *)deviceUDID { return @""; /* Requires IOKit device tree access */ }

+ (NSUInteger)freeMemoryBytes {
    vm_statistics_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);
    host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&stats, &count);
    return stats.free_count * pageSize;
}

+ (NSUInteger)usedMemoryBytes {
    vm_statistics_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);
    host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&stats, &count);
    return (stats.active_count + stats.wire_count) * pageSize;
}

+ (NSUInteger)totalMemoryBytes {
    int mib[2] = {CTL_HW, HW_MEMSIZE};
    uint64_t mem;
    size_t size = sizeof(mem);
    sysctl(mib, 2, &mem, &size, NULL, 0);
    return (NSUInteger)mem;
}

+ (float)cpuUsage {
    /* Simplified: get overall CPU via host_processor_info */
    return 0.0f; /* TODO: implement via processor_info */
}

+ (NSUInteger)freeDiskMB {
    struct statfs stat;
    if (statfs("/var", &stat) == 0)
        return (NSUInteger)((double)stat.f_bavail * stat.f_bsize / (1024 * 1024));
    return 0;
}

+ (NSUInteger)totalDiskMB {
    struct statfs stat;
    if (statfs("/var", &stat) == 0)
        return (NSUInteger)((double)stat.f_blocks * stat.f_bsize / (1024 * 1024));
    return 0;
}

+ (float)thermalLevel { return 0.0f; /* TODO: IOKit thermal query */ }

@end

#pragma mark - CoreFoundation Fast String

@implementation CPFastString

+ (uint32_t)fnv1aHash:(const char *)str {
    uint32_t hash = 2166136261u;
    while (*str) { hash ^= (uint8_t)*str++; hash *= 16777619u; }
    return hash;
}

+ (BOOL)cString:(const char *)a equalsObjC:(NSString *)b {
    return strcmp(a, [b UTF8String]) == 0;
}

+ (NSString *)urlEncode:(NSString *)str {
    /* Use CF for zero-copy URL encoding */
    CFStringRef encoded = CFURLCreateStringByAddingPercentEscapes(
        kCFAllocatorDefault,
        (__bridge CFStringRef)str,
        NULL,
        CFSTR("!*'();:@&=+$,/?#[]"),
        kCFStringEncodingUTF8);
    return [(NSString *)encoded autorelease];
}

@end

#pragma mark - Syslog Reader

@implementation CPSyslogReader

+ (NSArray *)lastLines:(NSUInteger)count {
    /* Read /var/log/syslog tail */
    NSString *cmd = [NSString stringWithFormat:@"tail -%lu /var/log/syslog 2>/dev/null", (unsigned long)count];
    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return @[];

    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:count];
    char buf[1024];
    while (fgets(buf, sizeof(buf), fp) != NULL) {
        NSString *line = [[NSString stringWithUTF8String:buf]
            stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if ([line length] > 0) [lines addObject:line];
    }
    pclose(fp);
    return lines;
}

+ (NSArray *)linesMatching:(NSString *)pattern count:(NSUInteger)count {
    NSString *cmd = [NSString stringWithFormat:
        @"grep -i '%@' /var/log/syslog 2>/dev/null | tail -%lu",
        pattern, (unsigned long)count];
    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return @[];

    NSMutableArray *lines = [NSMutableArray array];
    char buf[1024];
    while (fgets(buf, sizeof(buf), fp) != NULL) {
        NSString *line = [[NSString stringWithUTF8String:buf]
            stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if ([line length] > 0) [lines addObject:line];
    }
    pclose(fp);
    return lines;
}

+ (NSArray *)recentCrashReports:(NSUInteger)count {
    NSString *dir = @"/var/mobile/Library/Logs/CrashReporter/";
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];

    /* Sort by modification date descending */
    NSMutableArray *sorted = [NSMutableArray array];
    for (NSString *f in files) {
        if (![f hasSuffix:@".plist"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:f];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        [sorted addObject:@{@"file": f, @"date": [attrs objectForKey:NSFileModificationDate] ?: [NSDate date]}];
    }
    [sorted sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[b objectForKey:@"date"] compare:[a objectForKey:@"date"]];
    }];

    NSUInteger max = MIN(count, [sorted count]);
    return [sorted subarrayWithRange:NSMakeRange(0, max)];
}

+ (NSDictionary *)analyzeCrashReport:(NSString *)path {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!plist) return @{@"error": @"Cannot read crash report"};

    NSString *desc = [plist objectForKey:@"description"];
    if (!desc) return @{@"error": @"No description in crash report"};

    /* Extract key info */
    NSMutableDictionary *analysis = [NSMutableDictionary dictionary];

    NSRange processRange = [desc rangeOfString:@"Process:"];
    NSRange exceptionRange = [desc rangeOfString:@"Exception Type:"];
    NSRange threadRange = [desc rangeOfString:@"Crashed Thread:"];

    if (processRange.location != NSNotFound) {
        NSRange lineEnd = [desc rangeOfString:@"\n" options:0 range:
            NSMakeRange(processRange.location, MIN(100, [desc length] - processRange.location))];
        if (lineEnd.location != NSNotFound)
            [analysis setObject:[desc substringWithRange:
                NSMakeRange(processRange.location, lineEnd.location - processRange.location)] forKey:@"process"];
    }
    if (exceptionRange.location != NSNotFound) {
        NSRange lineEnd = [desc rangeOfString:@"\n" options:0 range:
            NSMakeRange(exceptionRange.location, MIN(100, [desc length] - exceptionRange.location))];
        if (lineEnd.location != NSNotFound)
            [analysis setObject:[desc substringWithRange:
                NSMakeRange(exceptionRange.location, lineEnd.location - exceptionRange.location)] forKey:@"exception"];
    }

    return analysis;
}

@end

#pragma mark - Background Keepalive

@interface CPBackgroundKeepAlive () {
    SystemSoundID _silentSound;
    NSTimer *_timer;
    BOOL _active;
}
@end

@implementation CPBackgroundKeepAlive

+ (instancetype)shared {
    static CPBackgroundKeepAlive *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)startKeepAlive {
    if (_active) return;
    _active = YES;

    /* Play a silent sound every 10 seconds to keep the app alive.
       This is a well-known technique used by VoIP and navigation apps. */
    _timer = [NSTimer scheduledTimerWithTimeInterval:10.0
        target:self selector:@selector(_playSilence) userInfo:nil repeats:YES];
}

- (void)_playSilence {
    /* Play the shortest possible system sound (effectively silent keepalive) */
    AudioServicesPlaySystemSound(0); /* Sound ID 0 = no audible sound */
}

- (void)stopKeepAlive {
    [_timer invalidate]; _timer = nil;
    _active = NO;
}

- (BOOL)isKeepAliveActive { return _active; }

@end

#pragma mark - dyld Monitor

static CPDyldMonitor *_dyldMonitorInstance = nil;

static void _dyldImageAddedCallback(const struct mach_header *mh, intptr_t slide) {
    if (!_dyldMonitorInstance || !_dyldMonitorInstance.onLibraryLoaded) return;

    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_dyldMonitorInstance.onLibraryLoaded) {
                _dyldMonitorInstance.onLibraryLoaded(path);
            }
        });
    }
}

@implementation CPDyldMonitor

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ _dyldMonitorInstance = [[self alloc] init]; });
    return _dyldMonitorInstance;
}

- (void)startMonitoring {
    _dyld_register_func_for_add_image(_dyldImageAddedCallback);
}

- (void)stopMonitoring {
    /* dyld doesn't support unregistering — just nil the callback */
    self.onLibraryLoaded = nil;
}

+ (NSArray *)loadedLibraries {
    uint32_t count = _dyld_image_count();
    NSMutableArray *libs = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) [libs addObject:[NSString stringWithUTF8String:name]];
    }
    return libs;
}

- (void)dealloc { [_onLibraryLoaded release]; [super dealloc]; }

@end
