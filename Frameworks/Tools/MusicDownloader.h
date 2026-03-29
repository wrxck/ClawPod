/*
 * MusicDownloader.h
 * LegacyPodClaw - YouTube Music Search & Download
 *
 * Search YouTube, extract audio, download to device,
 * add to iPod music library with metadata and album art.
 */

#import <Foundation/Foundation.h>
#import "Agent.h"

@interface OCMusicDownloader : NSObject

+ (NSArray *)allTools;

/* Search YouTube and return top 5 results */
+ (OCToolDefinition *)searchMusicTool;

/* Download a YouTube video as MP3 and add to music library */
+ (OCToolDefinition *)downloadMusicTool;

/* List songs in the music library */
+ (OCToolDefinition *)listMusicTool;

@end
