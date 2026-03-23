/*
 * OCGuardrails.m
 * ClawPod - Safety Guardrails Implementation
 */

#import "OCGuardrails.h"
#import <sys/mount.h>

@implementation OCGuardrailVerdict
+ (OCGuardrailVerdict *)allow {
    OCGuardrailVerdict *v = [[[self alloc] init] autorelease];
    v.action = OCGuardrailAllow; return v;
}
+ (OCGuardrailVerdict *)confirmWithReason:(NSString *)reason {
    OCGuardrailVerdict *v = [[[self alloc] init] autorelease];
    v.action = OCGuardrailConfirm; v.reason = reason; return v;
}
+ (OCGuardrailVerdict *)blockWithReason:(NSString *)reason {
    OCGuardrailVerdict *v = [[[self alloc] init] autorelease];
    v.action = OCGuardrailBlock; v.reason = reason; return v;
}
- (void)dealloc { [_reason release]; [super dealloc]; }
@end

/* Protected path prefixes */
static NSArray *_hardBlockPaths = nil;
static NSArray *_confirmPaths = nil;
static NSArray *_secretPaths = nil;
static NSArray *_hardBlockCommands = nil;
static NSArray *_confirmCommands = nil;

@interface OCGuardrails () {
    NSMutableArray *_bashTimestamps;
    NSMutableArray *_writeTimestamps;
    NSDate *_lastSMSInsert;
}
@end

@implementation OCGuardrails

+ (void)initialize {
    _hardBlockPaths = [@[
        @"/System/", @"/usr/lib/", @"/usr/libexec/", @"/usr/sbin/",
        @"/sbin/", @"/bin/", @"/boot/", @"/var/stash/",
        @"/usr/share/firmware", @"/usr/standalone"
    ] retain];

    _confirmPaths = [@[
        @"/Library/MobileSubstrate/", @"/etc/",
        @"/var/mobile/Library/Preferences/com.apple.",
        @"/var/mobile/Library/Preferences/ai.openclaw"
    ] retain];

    _secretPaths = [@[
        @"/var/Keychains/", @"/var/mobile/Library/Mail/",
        @"/private/var/db/", @"/var/mobile/Library/Accounts/"
    ] retain];

    _hardBlockCommands = [@[
        @"rm -rf /", @"rm -rf /*", @"dd if=/dev/zero", @"dd of=/dev/",
        @"mkfs", @"newfs", @"nvram ", @"mount -o remount,rw /",
        @"killall backboardd", @"killall launchd",
        @"chmod 000 /", @"chmod -R 000", @"chown root:wheel /System"
    ] retain];

    _confirmCommands = [@[
        @"killall", @"reboot", @"halt", @"shutdown", @"sbreload",
        @"apt-get remove", @"dpkg -r", @"dpkg --purge",
        @"launchctl unload", @"launchctl stop"
    ] retain];
}

+ (instancetype)shared {
    static OCGuardrails *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _bashTimestamps = [[NSMutableArray alloc] init];
        _writeTimestamps = [[NSMutableArray alloc] init];
        _maxFileWriteSize = 1 * 1024 * 1024; /* 1MB */
    }
    return self;
}

- (void)dealloc {
    [_bashTimestamps release]; [_writeTimestamps release]; [_lastSMSInsert release];
    [super dealloc];
}

#pragma mark - Path Checks

- (OCGuardrailVerdict *)checkPath:(NSString *)path forOperation:(OCFileOp)op {
    if (!path) return [OCGuardrailVerdict blockWithReason:@"No path provided"];

    /* Resolve symlinks to prevent traversal */
    NSString *resolved = [path stringByResolvingSymlinksInPath];

    /* Read-only operations are more permissive */
    if (op == OCFileOpRead) {
        for (NSString *secret in _secretPaths) {
            if ([resolved hasPrefix:secret])
                return [OCGuardrailVerdict blockWithReason:
                    [NSString stringWithFormat:@"Access denied: %@ contains sensitive data", secret]];
        }
        return [OCGuardrailVerdict allow];
    }

    /* Write/edit/delete operations */
    for (NSString *blocked in _hardBlockPaths) {
        if ([resolved hasPrefix:blocked])
            return [OCGuardrailVerdict blockWithReason:
                [NSString stringWithFormat:@"BLOCKED: Cannot modify %@ (system-critical path)", blocked]];
    }

    for (NSString *confirm in _confirmPaths) {
        if ([resolved hasPrefix:confirm])
            return [OCGuardrailVerdict confirmWithReason:
                [NSString stringWithFormat:@"Modifying %@ requires confirmation", resolved]];
    }

    /* Check disk space for writes */
    if ((op == OCFileOpWrite || op == OCFileOpEdit) && ![self hasSufficientDiskSpace]) {
        return [OCGuardrailVerdict blockWithReason:
            [NSString stringWithFormat:@"Low disk space (%luMB free). Operation blocked.",
             (unsigned long)[self freeDiskSpaceMB]]];
    }

    return [OCGuardrailVerdict allow];
}

#pragma mark - Command Checks

- (OCGuardrailVerdict *)checkCommand:(NSString *)command {
    if (!command) return [OCGuardrailVerdict blockWithReason:@"No command"];

    NSString *lower = [command lowercaseString];

    /* Hard blocks */
    for (NSString *pattern in _hardBlockCommands) {
        if ([lower rangeOfString:pattern].location != NSNotFound)
            return [OCGuardrailVerdict blockWithReason:
                [NSString stringWithFormat:@"BLOCKED: Command contains dangerous pattern '%@'", pattern]];
    }

    /* Check for redirect/pipe to protected paths */
    for (NSString *blocked in _hardBlockPaths) {
        /* Check for > /System, >> /System, | dd of=/System, etc. */
        NSString *redir = [NSString stringWithFormat:@"> %@", blocked];
        NSString *redir2 = [NSString stringWithFormat:@">> %@", blocked];
        if ([command rangeOfString:redir].location != NSNotFound ||
            [command rangeOfString:redir2].location != NSNotFound)
            return [OCGuardrailVerdict blockWithReason:
                [NSString stringWithFormat:@"BLOCKED: Output redirect to protected path %@", blocked]];
    }

    /* Confirmation required */
    for (NSString *pattern in _confirmCommands) {
        if ([lower rangeOfString:pattern].location != NSNotFound)
            return [OCGuardrailVerdict confirmWithReason:
                [NSString stringWithFormat:@"Command '%@' is destructive and requires confirmation", command]];
    }

    /* rm with force flag on shallow paths */
    if ([lower rangeOfString:@"rm "].location != NSNotFound &&
        [lower rangeOfString:@"-rf"].location != NSNotFound) {
        return [OCGuardrailVerdict confirmWithReason:@"rm -rf requires confirmation"];
    }

    return [OCGuardrailVerdict allow];
}

#pragma mark - SQL Checks

- (OCGuardrailVerdict *)checkSQLQuery:(NSString *)query onDatabase:(NSString *)dbPath {
    if ([dbPath rangeOfString:@"sms.db"].location != NSNotFound) {
        NSString *upper = [query uppercaseString];
        if ([upper hasPrefix:@"DELETE"] || [upper hasPrefix:@"DROP"] ||
            [upper hasPrefix:@"ALTER"] || [upper hasPrefix:@"TRUNCATE"]) {
            if ([upper rangeOfString:@"CLAWPOD"].location == NSNotFound &&
                [upper rangeOfString:@"CLAWPOD-AI"].location == NSNotFound) {
                return [OCGuardrailVerdict blockWithReason:
                    @"BLOCKED: Cannot delete/modify non-ClawPod data in SMS database"];
            }
        }
    }
    return [OCGuardrailVerdict allow];
}

#pragma mark - Disk Space

- (BOOL)hasSufficientDiskSpace { return [self freeDiskSpaceMB] >= 50; }

- (NSUInteger)freeDiskSpaceMB {
    struct statfs stat;
    if (statfs("/var", &stat) == 0) {
        return (NSUInteger)((double)stat.f_bavail * stat.f_bsize / (1024 * 1024));
    }
    return 0;
}

#pragma mark - Rate Limiting

- (void)_pruneTimestamps:(NSMutableArray *)timestamps olderThan:(NSTimeInterval)seconds {
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-seconds];
    while ([timestamps count] > 0 && [[timestamps objectAtIndex:0] compare:cutoff] == NSOrderedAscending)
        [timestamps removeObjectAtIndex:0];
}

- (BOOL)allowBashExecution {
    [self _pruneTimestamps:_bashTimestamps olderThan:60];
    if ([_bashTimestamps count] >= 10) return NO;
    [_bashTimestamps addObject:[NSDate date]];
    return YES;
}

- (BOOL)allowFileWrite {
    [self _pruneTimestamps:_writeTimestamps olderThan:60];
    if ([_writeTimestamps count] >= 5) return NO;
    [_writeTimestamps addObject:[NSDate date]];
    return YES;
}

- (BOOL)allowSMSInsert {
    if (_lastSMSInsert && -[_lastSMSInsert timeIntervalSinceNow] < 5.0) return NO;
    [_lastSMSInsert release];
    _lastSMSInsert = [[NSDate date] retain];
    return YES;
}

@end
