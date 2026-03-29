/*
 * OCSystem.h
 * LegacyPodClaw - Deep System Integration Framework
 *
 * Provides low-level system access:
 * - CPDistributedMessagingCenter IPC client (talks to clawpodd)
 * - IOKit battery/hardware access
 * - CoreFoundation utilities (lower overhead than Foundation)
 * - Syslog reader and crash analyzer
 * - App sandbox reader (via daemon)
 * - dyld notifications (library load monitoring)
 * - Background keepalive (silent audio)
 */

#import <Foundation/Foundation.h>

#pragma mark - Daemon IPC Client

/*
 * Talks to the clawpodd daemon via CPDistributedMessagingCenter.
 * All methods are synchronous (block until daemon replies).
 */
@interface CPDaemonClient : NSObject

+ (instancetype)shared;
- (BOOL)isDaemonRunning;

/* System info (via daemon running as root) */
- (NSDictionary *)batteryInfo;
- (NSArray *)processList;
- (NSDictionary *)daemonStatus;
- (NSString *)sysctl:(NSString *)key;

/* File access (root-level, bypasses sandbox) */
- (NSString *)readFile:(NSString *)path;
- (NSDictionary *)readAppSandbox:(NSString *)appBundleId path:(NSString *)relativePath;

/* Crash monitoring */
- (NSArray *)recentCrashes;

/* Root command execution */
- (NSDictionary *)executeAsRoot:(NSString *)command;

@end

#pragma mark - IOKit Direct Hardware Access

@interface CPHardware : NSObject

/* Battery (via IOKit, no UIKit dependency) */
+ (NSInteger)batteryPercent;
+ (BOOL)isCharging;
+ (NSString *)powerSource;

/* Device identifiers */
+ (NSString *)serialNumber;
+ (NSString *)hardwareModel;
+ (NSString *)deviceUDID;

/* Memory (via mach) */
+ (NSUInteger)freeMemoryBytes;
+ (NSUInteger)usedMemoryBytes;
+ (NSUInteger)totalMemoryBytes;

/* CPU */
+ (float)cpuUsage;

/* Disk */
+ (NSUInteger)freeDiskMB;
+ (NSUInteger)totalDiskMB;

/* Thermal */
+ (float)thermalLevel;

@end

#pragma mark - CoreFoundation String Utilities

/*
 * Fast string operations using CF directly.
 * Avoids NSString autorelease overhead for hot paths.
 */
@interface CPFastString : NSObject

/* Hash a string (FNV-1a, much faster than NSString hash for short strings) */
+ (uint32_t)fnv1aHash:(const char *)str;

/* Compare without creating NSString */
+ (BOOL)cString:(const char *)a equalsObjC:(NSString *)b;

/* URL encode without NSString */
+ (NSString *)urlEncode:(NSString *)str;

@end

#pragma mark - Syslog Reader

@interface CPSyslogReader : NSObject

/* Read last N lines from syslog */
+ (NSArray *)lastLines:(NSUInteger)count;

/* Read lines matching a filter */
+ (NSArray *)linesMatching:(NSString *)pattern count:(NSUInteger)count;

/* Read crash reports from CrashReporter directory */
+ (NSArray *)recentCrashReports:(NSUInteger)count;

/* Analyze a crash report and return summary */
+ (NSDictionary *)analyzeCrashReport:(NSString *)path;

@end

#pragma mark - Background Keepalive

@interface CPBackgroundKeepAlive : NSObject

+ (instancetype)shared;

/* Start silent audio playback to keep the app alive in background */
- (void)startKeepAlive;
- (void)stopKeepAlive;
- (BOOL)isKeepAliveActive;

@end

#pragma mark - dyld Monitor

@interface CPDyldMonitor : NSObject

+ (instancetype)shared;

/* Start monitoring library loads */
- (void)startMonitoring;
- (void)stopMonitoring;

/* Get list of all loaded libraries */
+ (NSArray *)loadedLibraries;

/* Callback when a new library is loaded */
@property (nonatomic, copy) void(^onLibraryLoaded)(NSString *path);

@end
