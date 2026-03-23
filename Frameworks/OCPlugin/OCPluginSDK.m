/*
 * OCPluginSDK.m
 * ClawPod - Plugin System Implementation
 *
 * Loads .bundle files containing OCPlugin-conforming classes.
 * Bundles are loaded dynamically via NSBundle.
 */

#import "OCPluginSDK.h"

@interface OCPluginManager () {
    NSMutableDictionary *_plugins;  /* pluginId -> id<OCPlugin> */
    NSMutableDictionary *_configs;  /* pluginId -> NSDictionary */
}
@end

@implementation OCPluginManager

- (instancetype)init {
    if ((self = [super init])) {
        _plugins = [[NSMutableDictionary alloc] initWithCapacity:8];
        _configs = [[NSMutableDictionary alloc] initWithCapacity:8];
    }
    return self;
}

- (void)dealloc {
    /* Deactivate all plugins */
    for (id<OCPlugin> plugin in [_plugins allValues]) {
        [plugin deactivate];
    }
    [_plugins release]; [_configs release];
    [super dealloc];
}

- (NSArray *)loadedPlugins { return [_plugins allValues]; }

- (void)loadPluginsFromDirectory:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:directory error:nil];

    for (NSString *item in contents) {
        if ([item hasSuffix:@".bundle"]) {
            NSString *path = [directory stringByAppendingPathComponent:item];
            NSError *error = nil;
            if (![self loadPluginAtPath:path error:&error]) {
                NSLog(@"[Plugins] Failed to load %@: %@", item, error);
            }
        }
    }
}

- (BOOL)loadPluginAtPath:(NSString *)bundlePath error:(NSError **)error {
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (!bundle) {
        if (error) *error = [NSError errorWithDomain:@"OCPlugin" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load bundle"}];
        return NO;
    }

    if (![bundle load]) {
        if (error) *error = [NSError errorWithDomain:@"OCPlugin" code:-2
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load bundle code"}];
        return NO;
    }

    Class principalClass = [bundle principalClass];
    if (!principalClass || ![principalClass conformsToProtocol:@protocol(OCPlugin)]) {
        if (error) *error = [NSError errorWithDomain:@"OCPlugin" code:-3
            userInfo:@{NSLocalizedDescriptionKey: @"Bundle does not conform to OCPlugin"}];
        return NO;
    }

    id<OCPlugin> plugin = [[[principalClass alloc] init] autorelease];
    [self registerPlugin:plugin];

    NSLog(@"[Plugins] Loaded: %@ v%@", [plugin pluginName], [plugin pluginVersion]);
    return YES;
}

- (void)registerPlugin:(id<OCPlugin>)plugin {
    NSString *pid = [plugin pluginId];
    [_plugins setObject:plugin forKey:pid];

    /* Pass config if available */
    NSDictionary *config = [_configs objectForKey:pid];
    if (config && [plugin respondsToSelector:@selector(configDidChange:)]) {
        [plugin configDidChange:config];
    }

    [plugin activate];
}

- (void)unloadPlugin:(NSString *)pluginId {
    id<OCPlugin> plugin = [_plugins objectForKey:pluginId];
    if (plugin) {
        [plugin deactivate];
        [_plugins removeObjectForKey:pluginId];
    }
}

- (NSArray *)allPluginTools {
    NSMutableArray *tools = [NSMutableArray array];
    for (id<OCPlugin> plugin in [_plugins allValues]) {
        if ([plugin respondsToSelector:@selector(providedTools)]) {
            NSArray *t = [plugin providedTools];
            if (t) [tools addObjectsFromArray:t];
        }
    }
    return tools;
}

- (NSArray *)allPluginChannels {
    NSMutableArray *channels = [NSMutableArray array];
    for (id<OCPlugin> plugin in [_plugins allValues]) {
        if ([plugin respondsToSelector:@selector(providedChannels)]) {
            NSArray *c = [plugin providedChannels];
            if (c) [channels addObjectsFromArray:c];
        }
    }
    return channels;
}

- (void)setConfig:(NSDictionary *)config forPlugin:(NSString *)pluginId {
    [_configs setObject:config forKey:pluginId];
    id<OCPlugin> plugin = [_plugins objectForKey:pluginId];
    if (plugin && [plugin respondsToSelector:@selector(configDidChange:)]) {
        [plugin configDidChange:config];
    }
}

@end
