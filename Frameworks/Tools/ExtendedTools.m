/*
 * OCExtendedTools.m
 * ClawPod - Extended Tool Catalog Implementation
 */

#import "ExtendedTools.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

static OCStore *_memoryStore = nil;

@implementation OCExtendedTools

+ (NSArray *)allExtendedTools {
    return @[
        [self bashTool], [self processListTool],
        [self writeFileTool], [self editFileTool], [self listFilesTool], [self deleteFileTool],
        [self webSearchTool], [self webFetchTool],
        [self memoryStoreTool], [self memorySearchTool],
        [self networkInfoTool], [self storageTool], [self notifyTool]
    ];
}

+ (void)setupMemoryTables:(OCStore *)store {
    _memoryStore = store;
    [store execute:@"CREATE VIRTUAL TABLE IF NOT EXISTS agent_memory USING fts4(key, content, tags, timestamp)"
             error:nil];
}

#pragma mark - Bash

+ (OCToolDefinition *)bashTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"bash";
    t.toolDescription = @"Execute a shell command and return output. Use for system tasks.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"command": @{@"type": @"string"}},
        @"required": @[@"command"]};
    t.requiresConfirmation = YES;
    t.timeout = 30.0;
    t.handler = ^(NSDictionary *params, OCToolResultBlock cb) {
        NSString *cmd = [params objectForKey:@"command"];
        if (!cmd) { cb(@"Missing command", nil); return; }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            /* Use popen() since NSTask isn't available on iOS */
            NSString *fullCmd = [NSString stringWithFormat:@"%@ 2>&1", cmd];
            FILE *fp = popen([fullCmd UTF8String], "r");
            if (!fp) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    cb(@"Failed to execute command", nil);
                });
                return;
            }

            NSMutableString *output = [NSMutableString stringWithCapacity:1024];
            char buf[256];
            while (fgets(buf, sizeof(buf), fp) != NULL) {
                [output appendFormat:@"%s", buf];
                /* Cap at 16KB */
                if ([output length] > 16384) break;
            }
            int status = pclose(fp);

            NSMutableString *result = [NSMutableString stringWithFormat:@"Exit code: %d\n", WEXITSTATUS(status)];
            if ([output length] > 0) [result appendFormat:@"Output:\n%@", output];

            dispatch_async(dispatch_get_main_queue(), ^{ cb(result, nil); });
        });
    };
    return t;
}

+ (OCToolDefinition *)processListTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"process_list";
    t.toolDescription = @"List running processes on the device";
    t.inputSchema = @{@"type": @"object", @"properties": @{}};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
        size_t size;
        sysctl(mib, 4, NULL, &size, NULL, 0);
        struct kinfo_proc *procs = malloc(size);
        sysctl(mib, 4, procs, &size, NULL, 0);
        int count = (int)(size / sizeof(struct kinfo_proc));

        NSMutableArray *list = [NSMutableArray arrayWithCapacity:count];
        for (int i = 0; i < MIN(count, 50); i++) {
            [list addObject:[NSString stringWithFormat:@"%d: %s",
                procs[i].kp_proc.p_pid, procs[i].kp_proc.p_comm]];
        }
        free(procs);
        cb([list componentsJoinedByString:@"\n"], nil);
    };
    return t;
}

#pragma mark - File Ops

+ (OCToolDefinition *)writeFileTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"write_file";
    t.toolDescription = @"Write content to a file on disk";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"path": @{@"type": @"string"}, @"content": @{@"type": @"string"}},
        @"required": @[@"path", @"content"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *path = [p objectForKey:@"path"];
        NSString *content = [p objectForKey:@"content"];
        NSError *e = nil;
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&e];
        cb(e ? [e localizedDescription] : [NSString stringWithFormat:@"Written %lu bytes to %@",
            (unsigned long)[content length], path], e);
    };
    return t;
}

+ (OCToolDefinition *)editFileTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"edit_file";
    t.toolDescription = @"Edit a file by replacing text. Provide old_text and new_text.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"path": @{@"type": @"string"},
            @"old_text": @{@"type": @"string"}, @"new_text": @{@"type": @"string"}},
        @"required": @[@"path", @"old_text", @"new_text"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *path = [p objectForKey:@"path"];
        NSError *e = nil;
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
        if (e) { cb(nil, e); return; }
        NSString *oldText = [p objectForKey:@"old_text"];
        NSString *newText = [p objectForKey:@"new_text"];
        if ([content rangeOfString:oldText].location == NSNotFound) {
            cb(@"old_text not found in file", nil); return;
        }
        NSString *updated = [content stringByReplacingOccurrencesOfString:oldText withString:newText];
        [updated writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&e];
        cb(e ? [e localizedDescription] : @"File edited successfully", e);
    };
    return t;
}

+ (OCToolDefinition *)listFilesTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_files";
    t.toolDescription = @"List files in a directory";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"path": @{@"type": @"string"}},
        @"required": @[@"path"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *path = [p objectForKey:@"path"];
        NSError *e = nil;
        NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&e];
        if (e) { cb(nil, e); return; }
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *item in items) {
            NSString *full = [path stringByAppendingPathComponent:item];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:nil];
            BOOL isDir = [[attrs objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory];
            unsigned long long size = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
            [lines addObject:[NSString stringWithFormat:@"%@ %8llu %@",
                isDir ? @"d" : @"-", size, item]];
        }
        cb([lines componentsJoinedByString:@"\n"], nil);
    };
    return t;
}

+ (OCToolDefinition *)deleteFileTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"delete_file";
    t.toolDescription = @"Delete a file from disk";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"path": @{@"type": @"string"}},
        @"required": @[@"path"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSError *e = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[p objectForKey:@"path"] error:&e];
        cb(e ? [e localizedDescription] : @"Deleted", e);
    };
    return t;
}

#pragma mark - Web

+ (OCToolDefinition *)webSearchTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"web_search";
    t.toolDescription = @"Search the web using DuckDuckGo. Returns top results.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"query": @{@"type": @"string"}},
        @"required": @[@"query"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *q = [p objectForKey:@"query"];
        NSString *encoded = [q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *url = [NSString stringWithFormat:
            @"https://html.duckduckgo.com/html/?q=%@", encoded];
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
            cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:15];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
            completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
            if (e) { cb(nil, e); return; }
            NSString *html = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
            /* Extract result snippets - simple parsing */
            NSMutableArray *results = [NSMutableArray array];
            NSArray *chunks = [html componentsSeparatedByString:@"result__snippet"];
            for (NSUInteger i = 1; i < MIN([chunks count], 6); i++) {
                NSString *chunk = [chunks objectAtIndex:i];
                /* Strip HTML tags roughly */
                NSMutableString *clean = [chunk mutableCopy];
                while (YES) {
                    NSRange open = [clean rangeOfString:@"<"];
                    if (open.location == NSNotFound) break;
                    NSRange close = [clean rangeOfString:@">" options:0
                        range:NSMakeRange(open.location, [clean length] - open.location)];
                    if (close.location == NSNotFound) break;
                    [clean deleteCharactersInRange:NSMakeRange(open.location,
                        close.location - open.location + 1)];
                }
                NSString *trimmed = [clean stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([trimmed length] > 10 && [trimmed length] < 500) {
                    [results addObject:[NSString stringWithFormat:@"%lu. %@", (unsigned long)i, trimmed]];
                }
                [clean release];
            }
            cb([results count] > 0 ? [results componentsJoinedByString:@"\n\n"]
                                    : @"No results found", nil);
        }];
    };
    return t;
}

+ (OCToolDefinition *)webFetchTool {
    /* Reuse the existing http_fetch from OCBuiltinTools */
    return [OCBuiltinTools httpFetchTool];
}

#pragma mark - Memory

+ (OCToolDefinition *)memoryStoreTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"memory_store";
    t.toolDescription = @"Store information in persistent memory for future reference";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"key": @{@"type": @"string"}, @"content": @{@"type": @"string"},
            @"tags": @{@"type": @"string"}},
        @"required": @[@"key", @"content"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_memoryStore) { cb(@"Memory store not initialized", nil); return; }
        [_memoryStore execute:@"INSERT OR REPLACE INTO agent_memory(key, content, tags, timestamp) VALUES(?,?,?,?)"
            params:@[[p objectForKey:@"key"], [p objectForKey:@"content"],
                [p objectForKey:@"tags"] ?: @"",
                @([[NSDate date] timeIntervalSince1970])]
            error:nil];
        cb(@"Stored in memory", nil);
    };
    return t;
}

+ (OCToolDefinition *)memorySearchTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"memory_search";
    t.toolDescription = @"Search persistent memory using full-text search";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"query": @{@"type": @"string"}},
        @"required": @[@"query"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_memoryStore) { cb(@"Memory store not initialized", nil); return; }
        NSMutableArray *results = [NSMutableArray array];
        [_memoryStore query:@"SELECT key, content, tags FROM agent_memory WHERE content MATCH ? LIMIT 10"
            params:@[[p objectForKey:@"query"]]
            enumerate:^(OCStoreRow *row, BOOL *stop) {
                [results addObject:[NSString stringWithFormat:@"[%@] %@ (tags: %@)",
                    [row stringForColumn:@"key"],
                    [row stringForColumn:@"content"],
                    [row stringForColumn:@"tags"]]];
            } error:nil];
        cb([results count] > 0 ? [results componentsJoinedByString:@"\n---\n"]
                                : @"No memories found", nil);
    };
    return t;
}

#pragma mark - System Info

+ (OCToolDefinition *)networkInfoTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"network_info";
    t.toolDescription = @"Get network interfaces and IP addresses";
    t.inputSchema = @{@"type": @"object", @"properties": @{}};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSMutableArray *info = [NSMutableArray array];
        struct ifaddrs *interfaces = NULL;
        if (getifaddrs(&interfaces) == 0) {
            struct ifaddrs *addr = interfaces;
            while (addr) {
                if (addr->ifa_addr->sa_family == AF_INET) {
                    char buf[INET_ADDRSTRLEN];
                    inet_ntop(AF_INET, &((struct sockaddr_in *)addr->ifa_addr)->sin_addr, buf, sizeof(buf));
                    [info addObject:[NSString stringWithFormat:@"%s: %s", addr->ifa_name, buf]];
                }
                addr = addr->ifa_next;
            }
            freeifaddrs(interfaces);
        }
        cb([info componentsJoinedByString:@"\n"], nil);
    };
    return t;
}

+ (OCToolDefinition *)storageTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"storage_info";
    t.toolDescription = @"Get disk space information";
    t.inputSchema = @{@"type": @"object", @"properties": @{}};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        struct statfs stat;
        NSMutableArray *info = [NSMutableArray array];
        if (statfs("/", &stat) == 0) {
            double total = (double)stat.f_blocks * stat.f_bsize / (1024*1024);
            double free = (double)stat.f_bavail * stat.f_bsize / (1024*1024);
            [info addObject:[NSString stringWithFormat:@"/: %.0fMB free / %.0fMB total", free, total]];
        }
        if (statfs("/var", &stat) == 0) {
            double total = (double)stat.f_blocks * stat.f_bsize / (1024*1024);
            double free = (double)stat.f_bavail * stat.f_bsize / (1024*1024);
            [info addObject:[NSString stringWithFormat:@"/var: %.0fMB free / %.0fMB total", free, total]];
        }
        cb([info componentsJoinedByString:@"\n"], nil);
    };
    return t;
}

+ (OCToolDefinition *)batteryTool {
    return [OCBuiltinTools deviceInfoTool]; /* Already includes device info */
}

+ (OCToolDefinition *)notifyTool {
    return [OCBuiltinTools timerTool]; /* Timer tool already does notifications */
}

#pragma mark - Stubs for heavy tools

+ (OCToolDefinition *)imageDescribeTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"image_describe";
    t.toolDescription = @"Describe an image using a vision model (requires image URL or base64)";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"image_url": @{@"type": @"string"}},
        @"required": @[@"image_url"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        cb(@"Image description not yet available on this device (requires vision model API)", nil);
    };
    return t;
}

+ (OCToolDefinition *)imageGenerateTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"image_generate";
    t.toolDescription = @"Generate an image from a text prompt";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"prompt": @{@"type": @"string"}},
        @"required": @[@"prompt"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        cb(@"Image generation not yet available on this device", nil);
    };
    return t;
}

+ (OCToolDefinition *)spawnAgentTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"spawn_agent";
    t.toolDescription = @"Spawn a sub-agent to work on a specific task";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"task": @{@"type": @"string"}, @"model": @{@"type": @"string"}},
        @"required": @[@"task"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        /* TODO: Create a new OCAgent instance and run the task */
        cb(@"Sub-agent spawning not yet implemented on this device", nil);
    };
    return t;
}

@end
