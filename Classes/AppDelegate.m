/*
 * AppDelegate.m
 * ClawPod - Main Application Delegate Implementation
 *
 * Initializes all services, manages lifecycle, handles
 * memory warnings aggressively for 256MB device.
 */

#import "AppDelegate.h"
#import "OCRootViewController.h"
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

    /* Initialize local agent (PicoClaw-inspired lightweight runtime) */
    _localAgent = [[OCAgent alloc] init];
    _localAgent.maxContextTokens = 2048;  /* Conservative for 256MB device */
    _localAgent.maxResponseTokens = 512;
    _localAgent.systemPrompt = @"You are Molty, a helpful AI assistant running "
        @"on an iPod Touch via ClawPod. Be concise and efficient.";

    /* Register built-in tools */
    for (OCToolDefinition *tool in [OCBuiltinTools deviceTools]) {
        [_localAgent registerTool:tool];
    }

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
