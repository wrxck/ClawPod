/*
 * AppDelegate.m
 * ClawPod - Main Application Delegate Implementation
 *
 * Initializes all services, manages lifecycle, handles
 * memory warnings aggressively for 256MB device.
 */

#import "AppDelegate.h"
#import "RootViewController.h"
#import "ExtendedTools.h"
#import "SystemMCP.h"
#import "NotesReminders.h"
#import "MusicDownloader.h"
#import <notify.h>

@implementation AppDelegate

static AppDelegate *_shared = nil;

+ (AppDelegate *)shared {
    return _shared;
}

#pragma mark - Application Lifecycle

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    _shared = self;

    /* Initialize memory monitor FIRST */
    OCMemoryMonitor *monitor = [OCMemoryMonitor sharedMonitor];
    monitor.appMemoryBudget = 80 * 1024 * 1024;  /* 80MB budget */
    [monitor startMonitoring];

    /* Register for memory pressure notifications */
    [monitor addPressureHandler:^(OCMemoryPressure pressure) {
        [self _handleMemoryPressure:pressure];
    }];

    /* Initialize SQLite store */
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *dbPath = [docsPath stringByAppendingPathComponent:@"openclaw.db"];

    _store = [[OCStore alloc] initWithPath:dbPath];
    NSError *dbError = nil;
    if (![_store open:&dbError]) {
        NSLog(@"[ClawPod] Failed to open database: %@", dbError);
    }

    /* Initialize settings */
    _settings = [[OCKeyValueStore alloc] initWithStore:_store tableName:@"settings"];
    [_settings setup:nil];

    /* Initialize gateway client */
    _gateway = [[OCGatewayClient alloc] init];
    _gateway.delegate = self;
    _gateway.clientDisplayName = [[UIDevice currentDevice] name];
    _gateway.autoReconnect = YES;

    /* Initialize session manager */
    _sessionManager = [[OCSessionManager alloc] initWithStore:_store
                                                gatewayClient:_gateway];
    _sessionManager.delegate = self;
    [_sessionManager setupSchema:nil];

    /* Initialize local agent */
    _localAgent = [[OCAgent alloc] init];
    _localAgent.maxContextTokens = 8192;
    _localAgent.maxResponseTokens = 4096;

    /* Set comprehensive system prompt */
    _localAgent.systemPrompt =
        @"You are ClawPod (Molty), an AI assistant with FULL system access on a jailbroken iPod Touch 4 (iOS 6.1.6, ARMv7, 256MB RAM). "
        @"You are like Claude Code but running directly on this device.\n\n"
        @"YOU HAVE TOOLS. Use them. You can:\n"
        @"- Execute ANY shell command (bash tool)\n"
        @"- Read, write, edit, delete files anywhere on the filesystem\n"
        @"- List directory contents\n"
        @"- Search the web\n"
        @"- Fetch URLs\n"
        @"- Create/read/update/delete notes\n"
        @"- Create/complete/list reminders with due dates\n"
        @"- Send messages to the user via Messages.app\n"
        @"- Post system notification banners\n"
        @"- Control brightness, volume, launch apps\n"
        @"- Lock the device, vibrate, open URLs\n"
        @"- Get device state (battery, network, disk)\n"
        @"- Search persistent memory\n"
        @"- Get date/time, clipboard, network info, storage info\n"
        @"- List running processes\n"
        @"- Search YouTube for music (search_music tool)\n"
        @"- Download songs and add to the Music library (download_music tool, requires music proxy)\n"
        @"- List songs in the music library (list_music tool)\n\n"
        @"ALWAYS use tools when the user asks you to do something on the device. "
        @"Don't say you can't — you CAN. You have root access.\n\n"
        @"Safety: /System, /sbin, /bin, /boot are protected. Check disk space before large writes. "
        @"Destructive commands need confirmation.\n\n"
        @"Be concise but thorough. Show command output when relevant.";

    /* Register ALL tools (deduplicate by name) */
    NSMutableSet *seen = [NSMutableSet setWithCapacity:50];
    NSArray *allSources = @[
        [OCBuiltinTools deviceTools],
        [OCExtendedTools allExtendedTools],
        [OCSystemMCPTools allSystemTools],
        [OCNotesReminders allTools],
        [OCMusicDownloader allTools]
    ];
    for (NSArray *tools in allSources) {
        for (OCToolDefinition *tool in tools) {
            if (tool.name && ![seen containsObject:tool.name]) {
                [_localAgent registerTool:tool];
                [seen addObject:tool.name];
            }
        }
    }
    NSLog(@"[ClawPod] %lu tools registered", (unsigned long)[seen count]);

    /* Setup notes/reminders database */
    [OCNotesReminders setupWithStore:_store];
    [OCExtendedTools setupMemoryTables:_store];

    /* Load local sessions immediately (don't wait for gateway) */
    [_sessionManager loadSessions];

    /* Load settings from PreferenceLoader shared prefs */
    [self loadConnectionSettings];
    [self _registerPrefsNotifications];

    /* Create UI */
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _rootViewController = [[OCRootViewController alloc] init];

    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:_rootViewController];

    /* iOS 6 style navigation bar */
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.18f green:0.20f blue:0.25f alpha:1.0f];

    _window.rootViewController = nav;
    [_window makeKeyAndVisible];
    [nav release];

    /* Auto-connect if we have saved settings */
    if (_gateway.host && [_gateway.host length] > 0) {
        [self connectToGateway];
    }

    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    NSLog(@"[ClawPod] System memory warning received!");
    [self _handleMemoryPressure:OCMemoryPressureCritical];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    /* Save state and reduce memory footprint */
    [_sessionManager trimMessageWindows];
    [_store optimize];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    /* Reconnect if needed */
    if (_gateway.connectionState == OCGatewayStateDisconnected &&
        _gateway.host && [_gateway.host length] > 0) {
        [self connectToGateway];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self saveConnectionSettings];
    [_store close];
}

#pragma mark - Memory Management

- (void)_handleMemoryPressure:(OCMemoryPressure)pressure {
    switch (pressure) {
        case OCMemoryPressureWarning:
            NSLog(@"[ClawPod] Memory pressure: WARNING");
            [_sessionManager trimMessageWindows];
            break;

        case OCMemoryPressureCritical:
            NSLog(@"[ClawPod] Memory pressure: CRITICAL");
            [_sessionManager trimMessageWindows];
            [_store vacuum];
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            break;

        case OCMemoryPressureTerminal:
            NSLog(@"[ClawPod] Memory pressure: TERMINAL - shedding everything");
            [_sessionManager trimMessageWindows];
            [_localAgent clearContext];
            [_store vacuum];
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            break;

        default:
            break;
    }
}

#pragma mark - Connection

- (void)connectToGateway {
    if (_gateway.connectionState != OCGatewayStateDisconnected) return;
    [_gateway connect];
}

- (void)disconnectFromGateway {
    [_gateway disconnect];
}

#pragma mark - Settings (read from PreferenceLoader shared prefs)

- (void)saveConnectionSettings {
    /* Device token is the only thing the app writes back */
    if (_gateway.authConfig.deviceToken) {
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:
            @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"] ?: [NSMutableDictionary dictionary];
        [prefs setObject:_gateway.authConfig.deviceToken forKey:@"deviceToken"];
        [prefs writeToFile:@"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist" atomically:YES];
    }
}

- (void)loadConnectionSettings {
    /* Read from shared preferences file (written by Settings.app PreferenceBundle) */
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"];

    _gateway.host = [prefs objectForKey:@"gatewayHost"];
    NSString *portStr = [prefs objectForKey:@"gatewayPort"];
    _gateway.port = portStr ? [portStr integerValue] : 18789;
    if (_gateway.port == 0) _gateway.port = 18789;
    _gateway.useTLS = [[prefs objectForKey:@"useTLS"] boolValue];
    _gateway.allowSelfSignedCerts = [[prefs objectForKey:@"allowSelfSigned"] boolValue];

    OCGatewayAuthConfig *auth = [[OCGatewayAuthConfig alloc] init];
    auth.token = [prefs objectForKey:@"authToken"];
    auth.password = [prefs objectForKey:@"authPassword"];
    auth.deviceToken = [prefs objectForKey:@"deviceToken"];
    _gateway.authConfig = auth;
    [auth release];

    /* Local agent config */
    OCModelConfig *modelCfg = [[OCModelConfig alloc] init];
    modelCfg.apiKey = [prefs objectForKey:@"apiKey"];
    modelCfg.modelId = [prefs objectForKey:@"modelId"] ?: @"claude-sonnet-4-20250514";
    modelCfg.baseURL = [prefs objectForKey:@"customBaseURL"];
    modelCfg.maxTokens = [[prefs objectForKey:@"maxResponseTokens"] intValue] ?: 512;
    modelCfg.contextWindow = [[prefs objectForKey:@"maxContextTokens"] intValue] ?: 2048;
    _localAgent.modelConfig = modelCfg;
    [modelCfg release];

    /* MCP servers */
    NSString *mcp1 = [prefs objectForKey:@"mcpServer1"];
    if (mcp1 && [mcp1 length] > 0) {
        OCMCPClient *client = [[[OCMCPClient alloc] initWithURL:mcp1 name:@"MCP1"] autorelease];
        [_localAgent addMCPServer:client];
        [client connect:nil];
    }
    NSString *mcp2 = [prefs objectForKey:@"mcpServer2"];
    if (mcp2 && [mcp2 length] > 0) {
        OCMCPClient *client = [[[OCMCPClient alloc] initWithURL:mcp2 name:@"MCP2"] autorelease];
        [_localAgent addMCPServer:client];
        [client connect:nil];
    }
}

- (void)_registerPrefsNotifications {
    /* Listen for Darwin notifications from Settings.app PreferenceBundle */
    int token;
    notify_register_dispatch("ai.openclaw.ios6/prefsChanged", &token,
        dispatch_get_main_queue(), ^(int t) {
            NSLog(@"[ClawPod] Preferences changed, reloading...");
            [self loadConnectionSettings];
        });
    notify_register_dispatch("ai.openclaw.ios6/connect", &token,
        dispatch_get_main_queue(), ^(int t) {
            [self connectToGateway];
        });
    notify_register_dispatch("ai.openclaw.ios6/disconnect", &token,
        dispatch_get_main_queue(), ^(int t) {
            [self disconnectFromGateway];
        });
}

#pragma mark - OCGatewayClientDelegate

- (void)gatewayClient:(OCGatewayClient *)client
       didChangeState:(OCGatewayConnectionState)state {
    [_rootViewController updateConnectionState:state];

    if (state == OCGatewayStateConnected) {
        [_sessionManager loadSessions];
    }
}

- (void)gatewayClient:(OCGatewayClient *)client
   didReceiveChatEvent:(OCGatewayChatEvent *)event {
    [_sessionManager handleChatEvent:event];
}

- (void)gatewayClient:(OCGatewayClient *)client
       didFailWithError:(NSError *)error {
    NSLog(@"[ClawPod] Gateway error: %@", error);
    [_rootViewController showError:[error localizedDescription]];
}

- (void)gatewayClient:(OCGatewayClient *)client
   didConnectWithServerInfo:(OCGatewayServerInfo *)info {
    NSLog(@"[ClawPod] Connected to gateway v%@ (conn: %@)",
          info.version, info.connectionId);
    /* Save device token if updated */
    [self saveConnectionSettings];
}

#pragma mark - OCSessionManagerDelegate

- (void)sessionManager:(id)manager didUpdateSession:(OCChatSession *)session {
    [_rootViewController reloadSessions];
}

- (void)sessionManager:(id)manager didReceiveMessage:(OCMessage *)message
             inSession:(OCChatSession *)session {
    [_rootViewController didReceiveMessage:message inSession:session];
}

- (void)sessionManager:(id)manager didUpdateStreamingMessage:(OCMessage *)message
             inSession:(OCChatSession *)session {
    [_rootViewController didUpdateStreamingMessage:message inSession:session];
}

- (void)dealloc {
    [[OCMemoryMonitor sharedMonitor] stopMonitoring];
    [_window release]; [_rootViewController release];
    [_gateway release]; [_store release]; [_sessionManager release];
    [_settings release]; [_localAgent release];
    [super dealloc];
}

@end
