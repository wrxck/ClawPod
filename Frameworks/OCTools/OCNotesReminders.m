/*
 * OCNotesReminders.m
 * ClawPod - Notes & Reminders CRUD Implementation
 *
 * Notes: stored in ClawPod's SQLite database (lightweight, no deps).
 * Reminders: stored in same DB with due dates and completion status.
 * Both are searchable and fully manageable by the AI.
 */

#import "OCNotesReminders.h"

static OCStore *_nrStore = nil;

@implementation OCNotesReminders

+ (void)setupWithStore:(OCStore *)store {
    _nrStore = store;
    [store execute:@"CREATE TABLE IF NOT EXISTS cp_notes ("
     @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
     @"title TEXT NOT NULL,"
     @"content TEXT,"
     @"tags TEXT,"
     @"created_at REAL DEFAULT (strftime('%s','now')),"
     @"updated_at REAL DEFAULT (strftime('%s','now'))"
     @")" error:nil];

    [store execute:@"CREATE TABLE IF NOT EXISTS cp_reminders ("
     @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
     @"title TEXT NOT NULL,"
     @"due_date REAL,"
     @"completed INTEGER DEFAULT 0,"
     @"priority INTEGER DEFAULT 0,"
     @"notes TEXT,"
     @"created_at REAL DEFAULT (strftime('%s','now'))"
     @")" error:nil];
}

+ (NSArray *)allTools {
    return @[
        [self createNoteTool], [self listNotesTool], [self readNoteTool],
        [self updateNoteTool], [self deleteNoteTool], [self searchNotesTool],
        [self createReminderTool], [self listRemindersTool],
        [self completeReminderTool], [self deleteReminderTool]
    ];
}

#pragma mark - Notes

+ (OCToolDefinition *)createNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"create_note";
    t.toolDescription = @"Create a new note with a title and optional content/tags";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{
            @"title": @{@"type": @"string"},
            @"content": @{@"type": @"string"},
            @"tags": @{@"type": @"string", @"description": @"Comma-separated tags"}
        }, @"required": @[@"title"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        [_nrStore execute:@"INSERT INTO cp_notes (title, content, tags) VALUES (?, ?, ?)"
            params:@[[p objectForKey:@"title"],
                [p objectForKey:@"content"] ?: [NSNull null],
                [p objectForKey:@"tags"] ?: [NSNull null]]
            error:nil];
        int64_t noteId = [_nrStore lastInsertRowId];
        cb([NSString stringWithFormat:@"Note created (ID: %lld): %@", noteId, [p objectForKey:@"title"]], nil);
    };
    return t;
}

+ (OCToolDefinition *)listNotesTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_notes";
    t.toolDescription = @"List all notes, optionally filtered by tag";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"tag": @{@"type": @"string"}}, @"required": @[]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        NSString *tag = [p objectForKey:@"tag"];
        NSString *sql = tag ? @"SELECT id, title, tags, updated_at FROM cp_notes WHERE tags LIKE ? ORDER BY updated_at DESC LIMIT 20"
                            : @"SELECT id, title, tags, updated_at FROM cp_notes ORDER BY updated_at DESC LIMIT 20";
        NSArray *params = tag ? @[[NSString stringWithFormat:@"%%%@%%", tag]] : nil;

        NSMutableArray *results = [NSMutableArray array];
        [_nrStore query:sql params:params enumerate:^(OCStoreRow *row, BOOL *stop) {
            [results addObject:[NSString stringWithFormat:@"[%lld] %@ (tags: %@)",
                [row int64ForColumn:@"id"],
                [row stringForColumn:@"title"] ?: @"",
                [row stringForColumn:@"tags"] ?: @"none"]];
        } error:nil];

        cb([results count] > 0 ? [results componentsJoinedByString:@"\n"] : @"No notes found", nil);
    };
    return t;
}

+ (OCToolDefinition *)readNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"read_note";
    t.toolDescription = @"Read the full content of a note by its ID";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        __block NSString *result = @"Note not found";
        [_nrStore query:@"SELECT title, content, tags FROM cp_notes WHERE id = ?"
            params:@[[p objectForKey:@"id"]]
            enumerate:^(OCStoreRow *row, BOOL *stop) {
                result = [NSString stringWithFormat:@"Title: %@\nTags: %@\n\n%@",
                    [row stringForColumn:@"title"] ?: @"",
                    [row stringForColumn:@"tags"] ?: @"none",
                    [row stringForColumn:@"content"] ?: @"(empty)"];
                *stop = YES;
            } error:nil];
        cb(result, nil);
    };
    return t;
}

+ (OCToolDefinition *)updateNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"update_note";
    t.toolDescription = @"Update a note's title, content, or tags by ID";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{
            @"id": @{@"type": @"integer"},
            @"title": @{@"type": @"string"},
            @"content": @{@"type": @"string"},
            @"tags": @{@"type": @"string"}
        }, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        NSMutableArray *sets = [NSMutableArray array];
        NSMutableArray *vals = [NSMutableArray array];
        if ([p objectForKey:@"title"]) { [sets addObject:@"title = ?"]; [vals addObject:[p objectForKey:@"title"]]; }
        if ([p objectForKey:@"content"]) { [sets addObject:@"content = ?"]; [vals addObject:[p objectForKey:@"content"]]; }
        if ([p objectForKey:@"tags"]) { [sets addObject:@"tags = ?"]; [vals addObject:[p objectForKey:@"tags"]]; }
        if ([sets count] == 0) { cb(@"Nothing to update", nil); return; }
        [sets addObject:@"updated_at = strftime('%s','now')"];
        [vals addObject:[p objectForKey:@"id"]];
        NSString *sql = [NSString stringWithFormat:@"UPDATE cp_notes SET %@ WHERE id = ?",
            [sets componentsJoinedByString:@", "]];
        [_nrStore execute:sql params:vals error:nil];
        cb([NSString stringWithFormat:@"Note %@ updated", [p objectForKey:@"id"]], nil);
    };
    return t;
}

+ (OCToolDefinition *)deleteNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"delete_note";
    t.toolDescription = @"Delete a note by its ID";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        [_nrStore execute:@"DELETE FROM cp_notes WHERE id = ?" params:@[[p objectForKey:@"id"]] error:nil];
        cb(@"Note deleted", nil);
    };
    return t;
}

+ (OCToolDefinition *)searchNotesTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"search_notes";
    t.toolDescription = @"Search notes by keyword in title or content";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"query": @{@"type": @"string"}}, @"required": @[@"query"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Notes not initialized", nil); return; }
        NSString *q = [NSString stringWithFormat:@"%%%@%%", [p objectForKey:@"query"]];
        NSMutableArray *results = [NSMutableArray array];
        [_nrStore query:@"SELECT id, title, substr(content, 1, 100) as snippet FROM cp_notes "
         @"WHERE title LIKE ? OR content LIKE ? ORDER BY updated_at DESC LIMIT 10"
            params:@[q, q]
            enumerate:^(OCStoreRow *row, BOOL *stop) {
                [results addObject:[NSString stringWithFormat:@"[%lld] %@: %@...",
                    [row int64ForColumn:@"id"],
                    [row stringForColumn:@"title"] ?: @"",
                    [row stringForColumn:@"snippet"] ?: @""]];
            } error:nil];
        cb([results count] > 0 ? [results componentsJoinedByString:@"\n"] : @"No matches", nil);
    };
    return t;
}

#pragma mark - Reminders

+ (OCToolDefinition *)createReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"create_reminder";
    t.toolDescription = @"Create a reminder with a title, optional due date (YYYY-MM-DD HH:MM), priority (0-2), and notes";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{
            @"title": @{@"type": @"string"},
            @"due_date": @{@"type": @"string", @"description": @"YYYY-MM-DD HH:MM format"},
            @"priority": @{@"type": @"integer", @"description": @"0=normal, 1=medium, 2=high"},
            @"notes": @{@"type": @"string"}
        }, @"required": @[@"title"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Reminders not initialized", nil); return; }
        NSNumber *dueTs = nil;
        NSString *dueDateStr = [p objectForKey:@"due_date"];
        if (dueDateStr) {
            NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
            [fmt setDateFormat:@"yyyy-MM-dd HH:mm"];
            NSDate *d = [fmt dateFromString:dueDateStr];
            if (!d) {
                [fmt setDateFormat:@"yyyy-MM-dd"];
                d = [fmt dateFromString:dueDateStr];
            }
            if (d) dueTs = @([d timeIntervalSince1970]);
        }

        [_nrStore execute:@"INSERT INTO cp_reminders (title, due_date, priority, notes) VALUES (?, ?, ?, ?)"
            params:@[[p objectForKey:@"title"],
                dueTs ?: [NSNull null],
                [p objectForKey:@"priority"] ?: @0,
                [p objectForKey:@"notes"] ?: [NSNull null]]
            error:nil];
        int64_t rid = [_nrStore lastInsertRowId];

        NSString *dueStr = dueDateStr ? [NSString stringWithFormat:@" (due: %@)", dueDateStr] : @"";
        cb([NSString stringWithFormat:@"Reminder created (ID: %lld): %@%@", rid, [p objectForKey:@"title"], dueStr], nil);
    };
    return t;
}

+ (OCToolDefinition *)listRemindersTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_reminders";
    t.toolDescription = @"List reminders. Shows incomplete by default, pass show_completed=true for all.";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"show_completed": @{@"type": @"boolean"}}, @"required": @[]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Reminders not initialized", nil); return; }
        BOOL showAll = [[p objectForKey:@"show_completed"] boolValue];
        NSString *sql = showAll
            ? @"SELECT id, title, due_date, completed, priority FROM cp_reminders ORDER BY due_date ASC LIMIT 30"
            : @"SELECT id, title, due_date, completed, priority FROM cp_reminders WHERE completed = 0 ORDER BY due_date ASC LIMIT 30";

        NSMutableArray *results = [NSMutableArray array];
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateFormat:@"yyyy-MM-dd HH:mm"];

        [_nrStore query:sql params:nil enumerate:^(OCStoreRow *row, BOOL *stop) {
            NSString *check = [row boolForColumn:@"completed"] ? @"[x]" : @"[ ]";
            NSString *pri = @"";
            NSInteger priority = [row integerForColumn:@"priority"];
            if (priority == 1) pri = @" !";
            if (priority >= 2) pri = @" !!";

            NSString *due = @"";
            double dueTs = [row doubleForColumn:@"due_date"];
            if (dueTs > 0) {
                due = [NSString stringWithFormat:@" (due: %@)",
                    [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:dueTs]]];
            }

            [results addObject:[NSString stringWithFormat:@"%@ [%lld] %@%@%@",
                check, [row int64ForColumn:@"id"],
                [row stringForColumn:@"title"] ?: @"", pri, due]];
        } error:nil];

        cb([results count] > 0 ? [results componentsJoinedByString:@"\n"] : @"No reminders", nil);
    };
    return t;
}

+ (OCToolDefinition *)completeReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"complete_reminder";
    t.toolDescription = @"Mark a reminder as completed by its ID";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Reminders not initialized", nil); return; }
        [_nrStore execute:@"UPDATE cp_reminders SET completed = 1 WHERE id = ?"
            params:@[[p objectForKey:@"id"]] error:nil];
        cb([NSString stringWithFormat:@"Reminder %@ completed", [p objectForKey:@"id"]], nil);
    };
    return t;
}

+ (OCToolDefinition *)deleteReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"delete_reminder";
    t.toolDescription = @"Delete a reminder by its ID";
    t.inputSchema = @{@"type": @"object",
        @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        if (!_nrStore) { cb(@"Reminders not initialized", nil); return; }
        [_nrStore execute:@"DELETE FROM cp_reminders WHERE id = ?" params:@[[p objectForKey:@"id"]] error:nil];
        cb(@"Reminder deleted", nil);
    };
    return t;
}

@end
