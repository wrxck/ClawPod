/*
 * OCExtendedTools.h
 * ClawPod - Extended Tool Catalog
 *
 * Bash execution, file operations, web search, image description,
 * system commands, memory search, multi-agent tools.
 */

#import <Foundation/Foundation.h>
#import "Agent.h"
#import "Store.h"

@interface OCExtendedTools : NSObject

/* Shell / System */
+ (OCToolDefinition *)bashTool;           // Execute shell commands
+ (OCToolDefinition *)processListTool;    // List running processes

/* File Operations */
+ (OCToolDefinition *)writeFileTool;      // Write file to disk
+ (OCToolDefinition *)editFileTool;       // Edit file (search & replace)
+ (OCToolDefinition *)listFilesTool;      // List directory contents
+ (OCToolDefinition *)deleteFileTool;     // Delete a file

/* Web */
+ (OCToolDefinition *)webSearchTool;      // Search via DuckDuckGo/Brave
+ (OCToolDefinition *)webFetchTool;       // Enhanced URL fetcher

/* Image */
+ (OCToolDefinition *)imageDescribeTool;  // Send image to vision model
+ (OCToolDefinition *)imageGenerateTool;  // Generate image via API

/* Memory / Knowledge */
+ (OCToolDefinition *)memoryStoreTool;    // Store in FTS memory
+ (OCToolDefinition *)memorySearchTool;   // Search FTS memory

/* Multi-Agent */
+ (OCToolDefinition *)spawnAgentTool;     // Spawn sub-agent for task

/* System Info */
+ (OCToolDefinition *)networkInfoTool;    // Network interfaces, IP address
+ (OCToolDefinition *)batteryTool;        // Battery level (if available)
+ (OCToolDefinition *)storageTool;        // Disk space info

/* Notifications */
+ (OCToolDefinition *)notifyTool;         // Send local notification

/* All extended tools */
+ (NSArray *)allExtendedTools;

/* Setup FTS tables for memory tools */
+ (void)setupMemoryTables:(OCStore *)store;

@end
