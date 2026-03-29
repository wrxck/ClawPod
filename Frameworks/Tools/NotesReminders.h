/*
 * OCNotesReminders.h
 * LegacyPodClaw - Notes & Reminders CRUD Tools
 *
 * Provides AI-accessible tools to create, read, update, and delete
 * notes and reminders. Uses the local SQLite store for notes and
 * the EventKit framework for reminders (iOS 6 compatible).
 */

#import <Foundation/Foundation.h>
#import "Agent.h"
#import "Store.h"

@interface OCNotesReminders : NSObject

/* Setup notes table in the app's SQLite database */
+ (void)setupWithStore:(OCStore *)store;

/* All CRUD tools for notes and reminders */
+ (NSArray *)allTools;

/* Notes tools */
+ (OCToolDefinition *)createNoteTool;
+ (OCToolDefinition *)listNotesTool;
+ (OCToolDefinition *)readNoteTool;
+ (OCToolDefinition *)updateNoteTool;
+ (OCToolDefinition *)deleteNoteTool;
+ (OCToolDefinition *)searchNotesTool;

/* Reminders tools */
+ (OCToolDefinition *)createReminderTool;
+ (OCToolDefinition *)listRemindersTool;
+ (OCToolDefinition *)completeReminderTool;
+ (OCToolDefinition *)deleteReminderTool;
+ (OCToolDefinition *)listReminderListsTool;
+ (OCToolDefinition *)createReminderListTool;

@end
