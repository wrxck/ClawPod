/*
 * ClawPod Daemon (clawpodd)
 * Persistent system service running as root via launchd.
 *
 * Responsibilities:
 * - Hosts CPDistributedMessagingCenter IPC server
 * - Runs the gateway server (HTTP + WebSocket)
 * - Monitors syslog for crashes/errors
 * - Manages background tasks
 * - Provides system-level services to the tweak and app
 *
 * Installed to: /usr/bin/clawpodd
 * LaunchDaemon: /Library/LaunchDaemons/pro.matthesketh.legacypodclaw.daemon.plist
 */

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <notify.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - CPDistributedMessagingCenter (AppSupport.framework)

/* Load CPDistributedMessagingCenter dynamically from AppSupport */
@interface CPDistributedMessagingCenter : NSObject
+ (instancetype)centerNamed:(NSString *)name;
- (void)runServerOnCurrentThread;
- (void)stopServer;
- (void)registerForMessageName:(NSString *)name target:(id)target selector:(SEL)selector;
- (BOOL)sendMessageName:(NSString *)name userInfo:(NSDictionary *)info;
- (NSDictionary *)sendMessageAndReceiveReplyName:(NSString *)name userInfo:(NSDictionary *)info;
@end

#pragma mark - IOKit Battery

static NSDictionary *_getBatteryInfo(void) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) return info;
    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (!sources) { CFRelease(blob); return info; }

    for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
        CFDictionaryRef src = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(sources, i));
        if (!src) continue;

        CFNumberRef curCap = CFDictionaryGetValue(src, CFSTR(kIOPSCurrentCapacityKey));
        CFNumberRef maxCap = CFDictionaryGetValue(src, CFSTR(kIOPSMaxCapacityKey));
        CFStringRef state = CFDictionaryGetValue(src, CFSTR(kIOPSPowerSourceStateKey));
        CFBooleanRef charging = CFDictionaryGetValue(src, CFSTR(kIOPSIsChargingKey));

        int cur = 0, max = 0;
        if (curCap) CFNumberGetValue(curCap, kCFNumberIntType, &cur);
        if (maxCap) CFNumberGetValue(maxCap, kCFNumberIntType, &max);

        [info setObject:@(max > 0 ? (cur * 100 / max) : 0) forKey:@"percent"];
        [info setObject:@(cur) forKey:@"currentCapacity"];
        [info setObject:@(max) forKey:@"maxCapacity"];
        [info setObject:(charging == kCFBooleanTrue ? @YES : @NO) forKey:@"charging"];
        if (state) [info setObject:(__bridge NSString *)state forKey:@"powerSource"];
    }

    CFRelease(sources);
    CFRelease(blob);
    return info;
}

#pragma mark - Syslog Monitor

static NSMutableArray *_recentCrashes = nil;
static NSDate *_lastSyslogCheck = nil;

static void _checkSyslogForCrashes(void) {
    /* Read recent crash reports */
    NSString *crashDir = @"/var/mobile/Library/Logs/CrashReporter/";
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:crashDir error:nil];

    NSDate *cutoff = _lastSyslogCheck ?: [NSDate dateWithTimeIntervalSinceNow:-300]; /* Last 5 min */
    [_lastSyslogCheck release];
    _lastSyslogCheck = [[NSDate date] retain];

    for (NSString *file in files) {
        if (![file hasSuffix:@".plist"]) continue;
        NSString *path = [crashDir stringByAppendingPathComponent:file];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *modified = [attrs objectForKey:NSFileModificationDate];
        if (modified && [modified compare:cutoff] == NSOrderedDescending) {
            [_recentCrashes addObject:@{
                @"file": file,
                @"date": [modified description],
                @"path": path
            }];
            /* Keep only last 20 */
            while ([_recentCrashes count] > 20) [_recentCrashes removeObjectAtIndex:0];
        }
    }
}

#pragma mark - Process Info

static NSArray *_getProcessList(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    sysctl(mib, 4, NULL, &size, NULL, 0);
    struct kinfo_proc *procs = malloc(size);
    sysctl(mib, 4, procs, &size, NULL, 0);
    int count = (int)(size / sizeof(struct kinfo_proc));

    NSMutableArray *list = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [list addObject:@{
            @"pid": @(procs[i].kp_proc.p_pid),
            @"name": [NSString stringWithUTF8String:procs[i].kp_proc.p_comm]
        }];
    }
    free(procs);
    return list;
}

#pragma mark - Sandbox Reader

static NSString *_readSandboxFile(NSString *path) {
    /* As root daemon, we can read any file on the device */
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error) return [NSString stringWithFormat:@"Error: %@", [error localizedDescription]];
    /* Cap at 32KB */
    if ([content length] > 32768) content = [content substringToIndex:32768];
    return content;
}

#pragma mark - Daemon IPC Handler

@interface ClawPodDaemon : NSObject {
    id _center; /* CPDistributedMessagingCenter, loaded at runtime */
    NSTimer *_syslogTimer;
    NSTimer *_batteryTimer;
    NSDictionary *_cachedBatteryInfo;
}
- (void)start;
@end

@implementation ClawPodDaemon

- (void)start {
    NSLog(@"[clawpodd] Starting ClawPod daemon v0.1.0");

    _recentCrashes = [[NSMutableArray alloc] init];

    /* Load AppSupport framework dynamically for CPDMC */
    dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);

    /* Create IPC server using runtime class lookup */
    Class CPDMCClass = NSClassFromString(@"CPDistributedMessagingCenter");
    if (!CPDMCClass) {
        NSLog(@"[clawpodd] FATAL: Cannot load CPDistributedMessagingCenter");
        return;
    }
    _center = [[CPDMCClass performSelector:@selector(centerNamed:)
                                withObject:@"pro.matthesketh.legacypodclaw.daemon"] retain];
    [_center performSelector:@selector(runServerOnCurrentThread)];

    /* Register message handlers via objc_msgSend (3-arg selector) */
    SEL regSel = @selector(registerForMessageName:target:selector:);
    typedef void (*RegFunc)(id, SEL, NSString *, id, SEL);
    RegFunc regMsg = (RegFunc)objc_msgSend;

    regMsg(_center, regSel, @"ping", self, @selector(handlePing:withUserInfo:));
    regMsg(_center, regSel, @"battery", self, @selector(handleBattery:withUserInfo:));
    regMsg(_center, regSel, @"processes", self, @selector(handleProcesses:withUserInfo:));
    regMsg(_center, regSel, @"crashes", self, @selector(handleCrashes:withUserInfo:));
    regMsg(_center, regSel, @"readFile", self, @selector(handleReadFile:withUserInfo:));
    regMsg(_center, regSel, @"execute", self, @selector(handleExecute:withUserInfo:));
    regMsg(_center, regSel, @"status", self, @selector(handleStatus:withUserInfo:));
    regMsg(_center, regSel, @"sandboxRead", self, @selector(handleSandboxRead:withUserInfo:));
    regMsg(_center, regSel, @"sysctl", self, @selector(handleSysctl:withUserInfo:));

    /* Start syslog monitor (check every 30s) */
    _syslogTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
        target:self selector:@selector(_checkSyslog) userInfo:nil repeats:YES];

    /* Cache battery info every 60s */
    _batteryTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
        target:self selector:@selector(_updateBattery) userInfo:nil repeats:YES];
    [self _updateBattery];

    NSLog(@"[clawpodd] IPC server running, %lu handlers registered",
        (unsigned long)9);

    /* Post notification that daemon is ready */
    notify_post("pro.matthesketh.legacypodclaw/daemonReady");
}

- (void)_checkSyslog { _checkSyslogForCrashes(); }
- (void)_updateBattery {
    [_cachedBatteryInfo release];
    _cachedBatteryInfo = [_getBatteryInfo() retain];
}

#pragma mark - IPC Handlers

- (NSDictionary *)handlePing:(NSString *)name withUserInfo:(NSDictionary *)info {
    return @{@"pong": @YES, @"uptime": @([self _uptime]), @"version": @"0.1.0"};
}

- (NSDictionary *)handleBattery:(NSString *)name withUserInfo:(NSDictionary *)info {
    return _cachedBatteryInfo ?: _getBatteryInfo();
}

- (NSDictionary *)handleProcesses:(NSString *)name withUserInfo:(NSDictionary *)info {
    return @{@"processes": _getProcessList()};
}

- (NSDictionary *)handleCrashes:(NSString *)name withUserInfo:(NSDictionary *)info {
    _checkSyslogForCrashes();
    return @{@"crashes": _recentCrashes ?: @[]};
}

- (NSDictionary *)handleReadFile:(NSString *)name withUserInfo:(NSDictionary *)info {
    NSString *path = [info objectForKey:@"path"];
    if (!path) return @{@"error": @"No path"};
    NSString *content = _readSandboxFile(path);
    return @{@"content": content ?: @""};
}

- (NSDictionary *)handleExecute:(NSString *)name withUserInfo:(NSDictionary *)info {
    NSString *cmd = [info objectForKey:@"command"];
    if (!cmd) return @{@"error": @"No command"};

    /* Execute as root */
    FILE *fp = popen([cmd UTF8String], "r");
    if (!fp) return @{@"error": @"popen failed"};

    NSMutableString *output = [NSMutableString stringWithCapacity:1024];
    char buf[256];
    while (fgets(buf, sizeof(buf), fp) != NULL) {
        [output appendFormat:@"%s", buf];
        if ([output length] > 32768) break;
    }
    int status = pclose(fp);

    return @{@"output": output, @"exitCode": @(WEXITSTATUS(status))};
}

- (NSDictionary *)handleStatus:(NSString *)name withUserInfo:(NSDictionary *)info {
    return @{
        @"running": @YES,
        @"uptime": @([self _uptime]),
        @"version": @"0.1.0",
        @"battery": _cachedBatteryInfo ?: @{},
        @"recentCrashes": @([_recentCrashes count]),
        @"pid": @(getpid())
    };
}

- (NSDictionary *)handleSandboxRead:(NSString *)name withUserInfo:(NSDictionary *)info {
    NSString *appId = [info objectForKey:@"appId"];
    NSString *relativePath = [info objectForKey:@"path"];
    if (!appId) return @{@"error": @"No appId"};

    /* Find app container */
    NSString *appsDir = @"/var/mobile/Applications/";
    NSArray *containers = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appsDir error:nil];
    for (NSString *uuid in containers) {
        NSString *containerPath = [appsDir stringByAppendingPathComponent:uuid];
        /* Check if this container belongs to the requested app */
        NSString *metadataPath = [containerPath stringByAppendingPathComponent:@"iTunesMetadata.plist"];
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
        NSString *bundleId = [metadata objectForKey:@"softwareVersionBundleId"];
        if ([bundleId isEqualToString:appId]) {
            NSString *fullPath = relativePath
                ? [containerPath stringByAppendingPathComponent:relativePath]
                : containerPath;
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
                BOOL isDir;
                [[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir];
                if (isDir) {
                    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fullPath error:nil];
                    return @{@"type": @"directory", @"contents": contents ?: @[]};
                } else {
                    NSString *content = _readSandboxFile(fullPath);
                    return @{@"type": @"file", @"content": content ?: @""};
                }
            }
            return @{@"error": @"Path not found in container"};
        }
    }
    return @{@"error": @"App container not found"};
}

- (NSDictionary *)handleSysctl:(NSString *)name withUserInfo:(NSDictionary *)info {
    NSString *key = [info objectForKey:@"key"];
    if (!key) return @{@"error": @"No key"};

    size_t size;
    sysctlbyname([key UTF8String], NULL, &size, NULL, 0);
    if (size == 0) return @{@"error": @"Unknown sysctl key"};

    char *buf = malloc(size);
    sysctlbyname([key UTF8String], buf, &size, NULL, 0);
    NSString *value = [[[NSString alloc] initWithBytes:buf length:size encoding:NSUTF8StringEncoding] autorelease];
    free(buf);

    return @{@"value": value ?: @"(binary data)"};
}

- (NSTimeInterval)_uptime {
    struct timeval boottime;
    size_t size = sizeof(boottime);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    sysctl(mib, 2, &boottime, &size, NULL, 0);
    return [[NSDate date] timeIntervalSince1970] - boottime.tv_sec;
}

@end

#pragma mark - Signal Handler

static volatile BOOL _running = YES;

static void _signalHandler(int sig) {
    NSLog(@"[clawpodd] Received signal %d, shutting down", sig);
    _running = NO;
    CFRunLoopStop(CFRunLoopGetMain());
}

#pragma mark - Main

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGTERM, _signalHandler);
        signal(SIGINT, _signalHandler);

        ClawPodDaemon *daemon = [[ClawPodDaemon alloc] init];
        [daemon start];

        /* Run the main run loop */
        while (_running) {
            @autoreleasepool {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10.0, NO);
            }
        }

        NSLog(@"[clawpodd] Daemon stopped");
        [daemon release];
    }
    return 0;
}
