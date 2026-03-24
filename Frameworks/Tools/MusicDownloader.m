/*
 * MusicDownloader.m
 * ClawPod - YouTube Music Search & Download
 *
 * Search: YouTube InnerTube API (WEB client) — works directly on device.
 * Download: Requires a music proxy server (yt-dlp bridge) running on LAN.
 *   The proxy handles signature deciphering that YouTube now requires.
 *   See ClawPodMCP/music_proxy.py for the server.
 *
 * The proxy URL is configured in Settings → ClawPod → Music Proxy URL.
 * Default: http://[gateway-host]:18790
 */

#import "MusicDownloader.h"
#import "TLSClient.h"
#import <sqlite3.h>

#define MEDIA_DB @"/var/mobile/Media/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
#define MUSIC_DIR @"/var/mobile/Media/iTunes_Control/Music"
#define YT_HOST @"www.youtube.com"

#pragma mark - Helpers

static int64_t _randomPID(void) {
    int64_t pid;
    arc4random_buf(&pid, sizeof(pid));
    if (pid == 0) pid = 1;
    return pid;
}

/*
 * Generate a title_order sort key from a string.
 * iTunes uses a locale-aware collation key, but we approximate with
 * a simple hash that preserves alphabetical ordering by first char.
 * The title_order_section is the alphabetical section (A=1, B=2, ... Z=26, #=27).
 */
static int64_t _titleSortKey(NSString *title) {
    NSString *lower = [[title lowercaseString] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    /* Skip leading "the ", "a ", "an " */
    if ([lower hasPrefix:@"the "]) lower = [lower substringFromIndex:4];
    else if ([lower hasPrefix:@"a "]) lower = [lower substringFromIndex:2];
    else if ([lower hasPrefix:@"an "]) lower = [lower substringFromIndex:3];

    int64_t key = 0;
    NSUInteger len = MIN([lower length], 8);
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [lower characterAtIndex:i];
        key = (key << 8) | (c & 0xFF);
    }
    /* Ensure positive and spread out */
    if (key < 0) key = -key;
    return key;
}

static int _titleSection(NSString *title) {
    NSString *lower = [[title lowercaseString] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([lower hasPrefix:@"the "]) lower = [lower substringFromIndex:4];
    else if ([lower hasPrefix:@"a "]) lower = [lower substringFromIndex:2];
    else if ([lower hasPrefix:@"an "]) lower = [lower substringFromIndex:3];
    if ([lower length] == 0) return 0;
    unichar c = [lower characterAtIndex:0];
    if (c >= 'a' && c <= 'z') return (c - 'a') + 1;
    return 27; /* # section for non-alpha */
}

static NSString *_getMusicProxyURL(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"];
    NSString *proxy = [prefs objectForKey:@"musicProxyURL"];
    if (proxy && [proxy length] > 0) return proxy;
    /* Default: same host as gateway, port 18790 */
    NSString *gwHost = [prefs objectForKey:@"gatewayHost"];
    if (gwHost && [gwHost length] > 0)
        return [NSString stringWithFormat:@"http://%@:18790", gwHost];
    return nil;
}

@implementation OCMusicDownloader

+ (NSArray *)allTools {
    return @[[self searchMusicTool], [self downloadMusicTool], [self listMusicTool]];
}

#pragma mark - YouTube Search (direct, no proxy needed)

/*
 * Search YouTube via InnerTube WEB client.
 * This works directly from the device — no proxy needed.
 */
+ (void)_searchYouTube:(NSString *)query
            completion:(void(^)(NSArray *results, NSError *error))completion {

    NSDictionary *body = @{
        @"context": @{@"client": @{
            @"clientName": @"WEB",
            @"clientVersion": @"2.20241126.01.00",
            @"hl": @"en", @"gl": @"US"
        }},
        @"query": query
    };

    NSData *jsonBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSDictionary *headers = @{
        @"Content-Type": @"application/json",
        @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    };

    NSString *url = [NSString stringWithFormat:@"https://%@/youtubei/v1/search", YT_HOST];

    [CPTLSClient request:url method:@"POST" headers:headers body:jsonBody
        completion:^(NSData *data, NSInteger status, NSError *error) {
            if (error || !data) {
                completion(nil, error ?: [NSError errorWithDomain:@"MusicDL" code:-1
                    userInfo:@{NSLocalizedDescriptionKey: @"No response from YouTube"}]);
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:[NSDictionary class]]) {
                NSString *preview = [[[NSString alloc] initWithData:
                    [data subdataWithRange:NSMakeRange(0, MIN(200, [data length]))]
                    encoding:NSUTF8StringEncoding] autorelease];
                completion(nil, [NSError errorWithDomain:@"MusicDL" code:-2
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Invalid JSON. Preview: %@", preview]}]);
                return;
            }

            /* Parse InnerTube search response */
            NSMutableArray *results = [NSMutableArray array];
            NSDictionary *contents = [json objectForKey:@"contents"];
            NSDictionary *twoCol = [contents objectForKey:@"twoColumnSearchResultsRenderer"];
            NSDictionary *primary = [twoCol objectForKey:@"primaryContents"];
            NSDictionary *sectionList = [primary objectForKey:@"sectionListRenderer"];
            NSArray *sections = [sectionList objectForKey:@"contents"];

            for (NSDictionary *section in sections) {
                NSDictionary *itemSection = [section objectForKey:@"itemSectionRenderer"];
                NSArray *items = [itemSection objectForKey:@"contents"];
                for (NSDictionary *item in items) {
                    NSDictionary *vr = [item objectForKey:@"videoRenderer"];
                    if (!vr) continue;
                    NSString *videoId = [vr objectForKey:@"videoId"];
                    if (!videoId) continue;

                    NSDictionary *titleObj = [vr objectForKey:@"title"];
                    NSArray *runs = [titleObj objectForKey:@"runs"];
                    NSString *title = ([runs count] > 0) ?
                        [[runs objectAtIndex:0] objectForKey:@"text"] : @"Unknown";

                    NSDictionary *ownerObj = [vr objectForKey:@"ownerText"];
                    NSArray *ownerRuns = [ownerObj objectForKey:@"runs"];
                    NSString *author = ([ownerRuns count] > 0) ?
                        [[ownerRuns objectAtIndex:0] objectForKey:@"text"] : @"Unknown";

                    NSDictionary *lenObj = [vr objectForKey:@"lengthText"];
                    NSString *durText = [lenObj objectForKey:@"simpleText"] ?: @"?:??";

                    [results addObject:@{
                        @"videoId": videoId, @"title": title,
                        @"author": author, @"duration": durText
                    }];
                    if ([results count] >= 5) break;
                }
                if ([results count] >= 5) break;
            }
            completion(results, nil);
        }];
}

#pragma mark - Music Proxy Download

/*
 * Download audio via music proxy server.
 * The proxy runs yt-dlp and returns the audio file + metadata.
 *
 * Proxy API:
 *   GET /info?v=VIDEO_ID  → {"title":"...","artist":"...","duration":213,"thumbnail":"..."}
 *   GET /audio?v=VIDEO_ID → raw audio file (m4a)
 */
+ (void)_getInfoViaProxy:(NSString *)videoId
              completion:(void(^)(NSDictionary *info, NSError *error))completion {

    NSString *proxyBase = _getMusicProxyURL();
    if (!proxyBase) {
        completion(nil, [NSError errorWithDomain:@"MusicDL" code:-10
            userInfo:@{NSLocalizedDescriptionKey:
                @"Music proxy not configured. Set Music Proxy URL in Settings → ClawPod, "
                @"or run: python3 ClawPodMCP/music_proxy.py on a computer on the same network."}]);
        return;
    }

    NSString *url = [NSString stringWithFormat:@"%@/info?v=%@", proxyBase, videoId];

    /* Use NSURLConnection for HTTP (non-TLS) proxy, CPTLSClient for HTTPS */
    if ([proxyBase hasPrefix:@"https://"]) {
        [CPTLSClient request:url method:@"GET" headers:nil body:nil
            completion:^(NSData *data, NSInteger status, NSError *error) {
                if (error || !data) {
                    completion(nil, error ?: [NSError errorWithDomain:@"MusicDL" code:-11
                        userInfo:@{NSLocalizedDescriptionKey: @"Proxy unreachable"}]);
                    return;
                }
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                completion(json, nil);
            }];
    } else {
        /* HTTP — use NSURLConnection */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
                cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
            NSURLResponse *resp = nil;
            NSError *err = nil;
            NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (err || !data) {
                    completion(nil, err ?: [NSError errorWithDomain:@"MusicDL" code:-11
                        userInfo:@{NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"Music proxy unreachable at %@. "
                            @"Run: python3 ClawPodMCP/music_proxy.py on a computer on the same network.", proxyBase]}]);
                    return;
                }
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (!json) {
                    completion(nil, [NSError errorWithDomain:@"MusicDL" code:-12
                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid response from proxy"}]);
                    return;
                }
                completion(json, nil);
            });
        });
    }
}

+ (void)_downloadAudioViaProxy:(NSString *)videoId toPath:(NSString *)path
                    completion:(void(^)(NSError *error))completion {

    NSString *proxyBase = _getMusicProxyURL();
    NSString *url = [NSString stringWithFormat:@"%@/audio?v=%@", proxyBase, videoId];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
            cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
        NSURLResponse *resp = nil;
        NSError *err = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data || [data length] < 4096) {
                completion(err ?: [NSError errorWithDomain:@"MusicDL" code:-13
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Audio download failed (%lu bytes)",
                            (unsigned long)[data length]]}]);
                return;
            }
            [data writeToFile:path atomically:YES];
            NSLog(@"[MusicDL] Saved %lu bytes to %@", (unsigned long)[data length], path);
            completion(nil);
        });
    });
}

#pragma mark - Tool Definitions

+ (OCToolDefinition *)searchMusicTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"search_music";
    t.toolDescription = @"Search YouTube for music. Returns top 5 results with video IDs. "
        @"Use download_music with a video_id to download and add to the Music app.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{
            @"query": @{@"type": @"string", @"description": @"Song name, artist, etc."}
        },
        @"required": @[@"query"]};

    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *query = [p objectForKey:@"query"];
        if (!query || [query length] == 0) { cb(@"Error: query is required", nil); return; }

        [OCMusicDownloader _searchYouTube:query completion:^(NSArray *results, NSError *error) {
            if (error || !results) {
                cb([NSString stringWithFormat:@"Search failed: %@",
                    [error localizedDescription] ?: @"unknown"], nil);
                return;
            }
            if ([results count] == 0) { cb(@"No results found.", nil); return; }
            NSMutableArray *output = [NSMutableArray array];
            for (NSUInteger i = 0; i < [results count]; i++) {
                NSDictionary *r = [results objectAtIndex:i];
                [output addObject:[NSString stringWithFormat:@"%lu. \"%@\" by %@ [%@] (video_id: %@)",
                    (unsigned long)(i+1), [r objectForKey:@"title"], [r objectForKey:@"author"],
                    [r objectForKey:@"duration"], [r objectForKey:@"videoId"]]];
            }
            cb([output componentsJoinedByString:@"\n"], nil);
        }];
    };
    return t;
}

+ (OCToolDefinition *)downloadMusicTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"download_music";
    t.toolDescription = @"Download a YouTube video as audio and add to the Music app. "
        @"Requires music proxy server running on LAN. Use search_music first.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{
            @"video_id": @{@"type": @"string", @"description": @"YouTube video ID"},
            @"title": @{@"type": @"string", @"description": @"Override song title (optional)"},
            @"artist": @{@"type": @"string", @"description": @"Override artist (optional)"},
            @"album": @{@"type": @"string", @"description": @"Album name (optional)"}
        },
        @"required": @[@"video_id"]};

    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *videoId = [p objectForKey:@"video_id"];
        if (!videoId || [videoId length] == 0) { cb(@"Error: video_id required", nil); return; }

        /* Step 1: Get metadata from proxy */
        [OCMusicDownloader _getInfoViaProxy:videoId completion:^(NSDictionary *info, NSError *error) {
            if (error) {
                cb([error localizedDescription], nil);
                return;
            }

            NSString *title = [p objectForKey:@"title"] ?: [info objectForKey:@"title"] ?: @"Unknown";
            NSString *artist = [p objectForKey:@"artist"] ?: [info objectForKey:@"artist"] ?: @"Unknown";
            NSString *album = [p objectForKey:@"album"] ?: [NSString stringWithFormat:@"%@ - Single", title];
            int durationSec = [[info objectForKey:@"duration"] intValue];

            /* Check duplicate */
            NSString *dup = [self _checkDuplicate:title artist:artist];
            if (dup) { cb(dup, nil); return; }

            /* Prepare file path */
            NSString *filename = [NSString stringWithFormat:@"CP%@.m4a",
                [[videoId substringToIndex:MIN(8, [videoId length])] uppercaseString]];
            NSString *folder = [NSString stringWithFormat:@"%@/F00", MUSIC_DIR];
            [[NSFileManager defaultManager] createDirectoryAtPath:folder
                withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *filepath = [NSString stringWithFormat:@"%@/%@", folder, filename];

            if ([[NSFileManager defaultManager] fileExistsAtPath:filepath]) {
                cb([NSString stringWithFormat:@"'%@' already downloaded.", title], nil);
                return;
            }

            /* Step 2: Download audio via proxy */
            [OCMusicDownloader _downloadAudioViaProxy:videoId toPath:filepath
                completion:^(NSError *dlError) {
                    if (dlError) {
                        cb([dlError localizedDescription], nil);
                        return;
                    }

                    NSDictionary *attrs = [[NSFileManager defaultManager]
                        attributesOfItemAtPath:filepath error:nil];
                    NSUInteger fileSize = [[attrs objectForKey:NSFileSize] unsignedIntegerValue];

                    /* Step 3: Add to MediaLibrary */
                    NSString *result = [self _addToMediaLibrary:title artist:artist album:album
                        filename:filename folder:@"iTunes_Control/Music/F00"
                        fileSize:fileSize durationMs:durationSec * 1000];

                    /* Kill Music app to force reload */
                    FILE *fp = popen("killall Music 2>/dev/null; killall iPod 2>/dev/null", "r");
                    if (fp) pclose(fp);

                    cb(result, nil);
                }];
        }];
    };
    return t;
}

#pragma mark - Duplicate Check

+ (NSString *)_checkDuplicate:(NSString *)title artist:(NSString *)artist {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2([MEDIA_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK)
        return nil;
    sqlite3_stmt *s;
    NSString *dup = nil;
    if (sqlite3_prepare_v2(db,
        "SELECT ie.title FROM item_extra ie WHERE ie.title = ?", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_text(s, 1, [title UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(s) == SQLITE_ROW)
            dup = [NSString stringWithFormat:@"'%@' is already in the Music library.", title];
        sqlite3_finalize(s);
    }
    sqlite3_close(db);
    return dup;
}

#pragma mark - MediaLibrary Database

+ (NSString *)_addToMediaLibrary:(NSString *)title artist:(NSString *)artist
    album:(NSString *)album filename:(NSString *)filename folder:(NSString *)folder
    fileSize:(NSUInteger)fileSize durationMs:(int)durationMs {

    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2([MEDIA_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL);
    if (rc != SQLITE_OK) {
        return [NSString stringWithFormat:@"Cannot open MediaLibrary DB (error %d). "
            @"File saved to %@/%@.", rc, MUSIC_DIR, filename];
    }

    /* Verify tables exist */
    BOOL hasItem = NO, hasItemExtra = NO;
    sqlite3_stmt *s;
    if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &s, NULL) == SQLITE_OK) {
        while (sqlite3_step(s) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(s, 0);
            if (name && strcmp(name, "item") == 0) hasItem = YES;
            if (name && strcmp(name, "item_extra") == 0) hasItemExtra = YES;
        }
        sqlite3_finalize(s);
    }
    if (!hasItem || !hasItemExtra) {
        sqlite3_close(db);
        return [NSString stringWithFormat:@"MediaLibrary DB schema incompatible. File saved to %@/%@.", MUSIC_DIR, filename];
    }

    int64_t itemPid = _randomPID();
    int64_t artistPid = _randomPID();
    int64_t albumPid = _randomPID();
    double now = [[NSDate date] timeIntervalSince1970];

    sqlite3_exec(db, "BEGIN TRANSACTION", NULL, NULL, NULL);

    /* Base location */
    int64_t baseLoc = 0;
    if (sqlite3_prepare_v2(db, "SELECT rowid FROM base_location WHERE path = ?", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_text(s, 1, [folder UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(s) == SQLITE_ROW) baseLoc = sqlite3_column_int64(s, 0);
        sqlite3_finalize(s);
    }
    if (baseLoc == 0 && sqlite3_prepare_v2(db,
        "INSERT INTO base_location (path) VALUES (?)", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_text(s, 1, [folder UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_step(s); baseLoc = sqlite3_last_insert_rowid(db); sqlite3_finalize(s);
    }

    /* Artist */
    if (sqlite3_prepare_v2(db,
        "SELECT item_artist_pid FROM item_artist WHERE item_artist = ?", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_text(s, 1, [artist UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(s) == SQLITE_ROW) artistPid = sqlite3_column_int64(s, 0);
        sqlite3_finalize(s);
    }
    if (sqlite3_prepare_v2(db,
        "INSERT OR IGNORE INTO item_artist (item_artist_pid, item_artist, item_artist_sort) VALUES (?, ?, ?)",
        -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(s, 1, artistPid);
        sqlite3_bind_text(s, 2, [artist UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(s, 3, [artist UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_step(s); sqlite3_finalize(s);
    }

    /* Album */
    if (sqlite3_prepare_v2(db,
        "SELECT album_pid FROM album WHERE album = ?", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_text(s, 1, [album UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(s) == SQLITE_ROW) albumPid = sqlite3_column_int64(s, 0);
        sqlite3_finalize(s);
    }
    if (sqlite3_prepare_v2(db,
        "INSERT OR IGNORE INTO album (album_pid, album, album_sort, album_artist_pid) VALUES (?, ?, ?, ?)",
        -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(s, 1, albumPid);
        sqlite3_bind_text(s, 2, [album UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(s, 3, [album UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(s, 4, artistPid);
        sqlite3_step(s); sqlite3_finalize(s);
    }

    /* Item — media_type=8 (music), location_kind_id for MPEG audio,
       disc_number=1, and sort keys for Music.app display */
    int64_t titleOrder = _titleSortKey(title);
    int titleSection = _titleSection(title);
    int64_t artistOrder = _titleSortKey(artist);
    int artistSection = _titleSection(artist);

    if (sqlite3_prepare_v2(db,
        "INSERT INTO item (item_pid, media_type, title_order, title_order_section, "
        "item_artist_pid, item_artist_order, item_artist_order_section, "
        "album_pid, album_artist_pid, "
        "disc_number, location_kind_id, base_location_id) "
        "VALUES (?, 8, ?, ?, ?, ?, ?, ?, ?, 1, -2428003283576516342, ?)",
        -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(s, 1, itemPid);
        sqlite3_bind_int64(s, 2, titleOrder);
        sqlite3_bind_int(s, 3, titleSection);
        sqlite3_bind_int64(s, 4, artistPid);
        sqlite3_bind_int64(s, 5, artistOrder);
        sqlite3_bind_int(s, 6, artistSection);
        sqlite3_bind_int64(s, 7, albumPid);
        sqlite3_bind_int64(s, 8, artistPid); /* album_artist_pid */
        sqlite3_bind_int64(s, 9, baseLoc);
        rc = sqlite3_step(s);
        sqlite3_finalize(s);
        if (rc != SQLITE_DONE) {
            NSLog(@"[MusicDL] item INSERT failed: %s", sqlite3_errmsg(db));
        }
    }

    /* Item extra (metadata) */
    if (sqlite3_prepare_v2(db,
        "INSERT INTO item_extra (item_pid, title, location, media_kind, "
        "total_time_ms, file_size, date_created, date_modified) "
        "VALUES (?, ?, ?, 1, ?, ?, ?, ?)", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(s, 1, itemPid);
        sqlite3_bind_text(s, 2, [title UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(s, 3, [filename UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(s, 4, durationMs);
        sqlite3_bind_int64(s, 5, (int64_t)fileSize);
        sqlite3_bind_int64(s, 6, (int64_t)now);
        sqlite3_bind_int64(s, 7, (int64_t)now);
        sqlite3_step(s); sqlite3_finalize(s);
    }

    sqlite3_exec(db, "COMMIT", NULL, NULL, NULL);
    sqlite3_close(db);

    return [NSString stringWithFormat:
        @"Downloaded '%@' by %@ (%d:%02d) and added to Music library. Open Music app to listen.",
        title, artist, durationMs/60000, (durationMs/1000)%60];
}

#pragma mark - List Music

+ (OCToolDefinition *)listMusicTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_music";
    t.toolDescription = @"List songs in the iPod Music library. Optionally search by title or artist.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"search": @{@"type": @"string", @"description": @"Search term (optional)"}},
        @"required": @[]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([MEDIA_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            cb(@"Cannot open MediaLibrary database", nil); return;
        }
        NSString *search = [p objectForKey:@"search"];
        NSMutableArray *results = [NSMutableArray array];
        sqlite3_stmt *s; int rc;
        if (search && [search length] > 0) {
            rc = sqlite3_prepare_v2(db,
                "SELECT ie.title, ia.item_artist, a.album FROM item i "
                "JOIN item_extra ie ON i.item_pid=ie.item_pid "
                "LEFT JOIN item_artist ia ON i.item_artist_pid=ia.item_artist_pid "
                "LEFT JOIN album a ON i.album_pid=a.album_pid "
                "WHERE ie.title LIKE ? OR ia.item_artist LIKE ? LIMIT 20", -1, &s, NULL);
            if (rc == SQLITE_OK) {
                NSString *like = [NSString stringWithFormat:@"%%%@%%", search];
                sqlite3_bind_text(s, 1, [like UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 2, [like UTF8String], -1, SQLITE_TRANSIENT);
            }
        } else {
            rc = sqlite3_prepare_v2(db,
                "SELECT ie.title, ia.item_artist, a.album FROM item i "
                "JOIN item_extra ie ON i.item_pid=ie.item_pid "
                "LEFT JOIN item_artist ia ON i.item_artist_pid=ia.item_artist_pid "
                "LEFT JOIN album a ON i.album_pid=a.album_pid "
                "ORDER BY ie.date_modified DESC LIMIT 20", -1, &s, NULL);
        }
        if (rc == SQLITE_OK) {
            while (sqlite3_step(s) == SQLITE_ROW) {
                const char *title = (const char *)sqlite3_column_text(s, 0);
                const char *artist = (const char *)sqlite3_column_text(s, 1);
                const char *album = (const char *)sqlite3_column_text(s, 2);
                [results addObject:[NSString stringWithFormat:@"%s - %s [%s]",
                    title ?: "?", artist ?: "?", album ?: "?"]];
            }
            sqlite3_finalize(s);
        }
        sqlite3_close(db);
        cb([results count] > 0 ? [results componentsJoinedByString:@"\n"] : @"No songs found.", nil);
    };
    return t;
}

@end
