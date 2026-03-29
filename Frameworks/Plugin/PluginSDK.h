/*
 * OCPluginSDK.h
 * LegacyPodClaw - Plugin System
 *
 * Loadable .bundle plugins that can add tools, channels, and providers.
 * Each plugin is an ObjC bundle with a principal class conforming to OCPlugin.
 */

#import <Foundation/Foundation.h>
#import "Agent.h"
#import "ChannelManager.h"

#pragma mark - Plugin Protocol

@protocol OCPlugin <NSObject>
@required
@property (nonatomic, readonly) NSString *pluginId;
@property (nonatomic, readonly) NSString *pluginName;
@property (nonatomic, readonly) NSString *pluginVersion;

- (void)activate;
- (void)deactivate;

@optional
/* Return tools this plugin provides */
- (NSArray *)providedTools;
/* Return channel instances this plugin provides */
- (NSArray *)providedChannels;
/* Called when plugin config changes */
- (void)configDidChange:(NSDictionary *)config;
@end

#pragma mark - Plugin Manager

@interface OCPluginManager : NSObject

@property (nonatomic, readonly) NSArray *loadedPlugins;

/* Load all plugins from a directory */
- (void)loadPluginsFromDirectory:(NSString *)directory;

/* Load a single plugin bundle */
- (BOOL)loadPluginAtPath:(NSString *)bundlePath error:(NSError **)error;

/* Unload a plugin */
- (void)unloadPlugin:(NSString *)pluginId;

/* Get all tools from all plugins */
- (NSArray *)allPluginTools;

/* Get all channels from all plugins */
- (NSArray *)allPluginChannels;

/* Register a plugin programmatically (not from bundle) */
- (void)registerPlugin:(id<OCPlugin>)plugin;

/* Plugin config (passed to plugins on activate) */
- (void)setConfig:(NSDictionary *)config forPlugin:(NSString *)pluginId;

@end
