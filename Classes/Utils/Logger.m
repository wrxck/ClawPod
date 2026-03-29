/*
 * OCLogger.m
 * LegacyPodClaw - Logger Implementation
 */

#import "Logger.h"

static const NSUInteger kMaxLogSize = 256 * 1024;  /* 256KB before rotation */
static const NSUInteger kBufferFlushSize = 4096;

@interface OCLogger () {
    NSFileHandle *_fileHandle;
    NSMutableData *_buffer;
    NSString *_logPath;
    dispatch_queue_t _logQueue;
}
@end

@implementation OCLogger

+ (instancetype)sharedLogger {
    static OCLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OCLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _minimumLevel = OCLogLevelInfo;
        _logQueue = dispatch_queue_create("pro.matthesketh.legacypodclaw.logger", DISPATCH_QUEUE_SERIAL);
        _buffer = [[NSMutableData alloc] initWithCapacity:kBufferFlushSize];

        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        _logPath = [[docsPath stringByAppendingPathComponent:@"openclaw.log"] retain];

        if (![[NSFileManager defaultManager] fileExistsAtPath:_logPath]) {
            [[NSFileManager defaultManager] createFileAtPath:_logPath contents:nil attributes:nil];
        }
        _fileHandle = [[NSFileHandle fileHandleForWritingAtPath:_logPath] retain];
        [_fileHandle seekToEndOfFile];
    }
    return self;
}

- (void)dealloc {
    [self flush];
    [_fileHandle closeFile]; [_fileHandle release];
    [_buffer release]; [_logPath release]; [_logQueue release];
    [super dealloc];
}

- (void)_log:(OCLogLevel)level format:(NSString *)format args:(va_list)args {
    if (level < _minimumLevel) return;

    NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    NSString *levelStr;
    switch (level) {
        case OCLogLevelDebug: levelStr = @"DBG"; break;
        case OCLogLevelInfo:  levelStr = @"INF"; break;
        case OCLogLevelWarn:  levelStr = @"WRN"; break;
        case OCLogLevelError: levelStr = @"ERR"; break;
    }

    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    [fmt setDateFormat:@"HH:mm:ss.SSS"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@ %@\n",
                      levelStr, [fmt stringFromDate:[NSDate date]], message];

    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];

    dispatch_async(_logQueue, ^{
        [_buffer appendData:lineData];

        if ([_buffer length] >= kBufferFlushSize) {
            [self _flushBuffer];
        }
    });

    /* Also log to console */
    NSLog(@"[LegacyPodClaw/%@] %@", levelStr, message);
}

- (void)debug:(NSString *)format, ... {
    va_list args; va_start(args, format);
    [self _log:OCLogLevelDebug format:format args:args];
    va_end(args);
}

- (void)info:(NSString *)format, ... {
    va_list args; va_start(args, format);
    [self _log:OCLogLevelInfo format:format args:args];
    va_end(args);
}

- (void)warn:(NSString *)format, ... {
    va_list args; va_start(args, format);
    [self _log:OCLogLevelWarn format:format args:args];
    va_end(args);
}

- (void)error:(NSString *)format, ... {
    va_list args; va_start(args, format);
    [self _log:OCLogLevelError format:format args:args];
    va_end(args);
}

- (void)flush {
    dispatch_sync(_logQueue, ^{
        [self _flushBuffer];
    });
}

- (void)_flushBuffer {
    if ([_buffer length] == 0) return;

    [_fileHandle writeData:_buffer];
    [_buffer setLength:0];

    /* Rotate if too large */
    unsigned long long fileSize = [_fileHandle offsetInFile];
    if (fileSize > kMaxLogSize) {
        [_fileHandle closeFile];
        NSString *oldPath = [_logPath stringByAppendingString:@".old"];
        [[NSFileManager defaultManager] removeItemAtPath:oldPath error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:_logPath toPath:oldPath error:nil];
        [[NSFileManager defaultManager] createFileAtPath:_logPath contents:nil attributes:nil];
        [_fileHandle release];
        _fileHandle = [[NSFileHandle fileHandleForWritingAtPath:_logPath] retain];
    }
}

@end
