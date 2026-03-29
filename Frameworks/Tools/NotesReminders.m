/*
 * NotesReminders.m
 * LegacyPodClaw - Notes & Reminders CRUD
 *
 * Writes directly to iOS Notes.app (notes.sqlite) and
 * Reminders.app (Calendar.sqlitedb) databases.
 */

#import "NotesReminders.h"
#import <sqlite3.h>

#define NOTES_DB @"/var/mobile/Library/Notes/notes.sqlite"
#define CALENDAR_DB @"/var/mobile/Library/Calendar/Calendar.sqlitedb"

static OCStore *_nrStore = nil;

@implementation OCNotesReminders

+ (void)setupWithStore:(OCStore *)store { _nrStore = store; }

+ (NSArray *)allTools {
    return @[
        [self createNoteTool], [self listNotesTool], [self readNoteTool],
        [self updateNoteTool], [self deleteNoteTool], [self searchNotesTool],
        [self createReminderTool], [self listRemindersTool],
        [self completeReminderTool], [self deleteReminderTool],
        [self listReminderListsTool], [self createReminderListTool]
    ];
}

#pragma mark - Notes

+ (OCToolDefinition *)createNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"create_note"; t.toolDescription = @"Create a note visible in iOS Notes app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"title": @{@"type": @"string"}, @"content": @{@"type": @"string"}}, @"required": @[@"title"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        NSString *title = [p objectForKey:@"title"];
        NSString *content = [p objectForKey:@"content"] ?: @"";

        sqlite3 *db = NULL;
        int rc = sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL);
        if (rc != SQLITE_OK) {
            cb([NSString stringWithFormat:@"Cannot open Notes DB (error %d): %s", rc,
                db ? sqlite3_errmsg(db) : "null"], nil);
            return;
        }

        /* Disable WAL temporarily for compatibility */
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE", NULL, NULL, NULL);

        int noteMax = 0, bodyMax = 0;
        sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='Note'", -1, &s, NULL) == SQLITE_OK) {
            if (sqlite3_step(s)==SQLITE_ROW) noteMax=sqlite3_column_int(s,0);
            sqlite3_finalize(s);
        }
        if (sqlite3_prepare_v2(db, "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='NoteBody'", -1, &s, NULL) == SQLITE_OK) {
            if (sqlite3_step(s)==SQLITE_ROW) bodyMax=sqlite3_column_int(s,0);
            sqlite3_finalize(s);
        }

        int nPK = noteMax+1, bPK = bodyMax+1;
        double now = [[NSDate date] timeIntervalSinceReferenceDate];

        /* Get next integer ID from ZNEXTID table (the REAL counter Notes.app uses) */
        int zcounter = 0;
        if (sqlite3_prepare_v2(db, "SELECT ZCOUNTER FROM ZNEXTID WHERE Z_PK=1", -1, &s, NULL) == SQLITE_OK) {
            if (sqlite3_step(s)==SQLITE_ROW) zcounter = sqlite3_column_int(s,0);
            sqlite3_finalize(s);
        }
        int intId = zcounter + 1;

        /* Body content — just the content text, same as Notes.app */
        NSString *bodyContent = [content length] > 0 ? content : title;

        /* Use parameterized queries (safe from SQL injection) */
        sqlite3_stmt *ins;

        /* Insert body */
        if (sqlite3_prepare_v2(db,
            "INSERT INTO ZNOTEBODY (Z_PK,Z_ENT,Z_OPT,ZOWNER,ZCONTENT) VALUES (?,4,1,?,?)",
            -1, &ins, NULL) == SQLITE_OK) {
            sqlite3_bind_int(ins, 1, bPK);
            sqlite3_bind_int(ins, 2, nPK);
            sqlite3_bind_text(ins, 3, [bodyContent UTF8String], -1, SQLITE_TRANSIENT);
            rc = sqlite3_step(ins);
            sqlite3_finalize(ins);
            if (rc != SQLITE_DONE) {
                sqlite3_close(db);
                cb([NSString stringWithFormat:@"Body insert failed: %s", sqlite3_errmsg(db)], nil);
                return;
            }
        }

        /* Insert note — match EXACTLY what Notes.app creates */
        if (sqlite3_prepare_v2(db,
            "INSERT INTO ZNOTE (Z_PK,Z_ENT,Z_OPT,"
            "ZCONTAINSCJK,ZCONTENTTYPE,ZDELETEDFLAG,ZEXTERNALFLAGS,ZEXTERNALSERVERINTID,"
            "ZINTEGERID,ZISBOOKKEEPINGENTRY,"
            "ZBODY,ZSTORE,ZCREATIONDATE,ZMODIFICATIONDATE,"
            "ZAUTHOR,ZGUID,ZSERVERID,ZSUMMARY,ZTITLE) "
            "VALUES (?,3,1,"
            "0,0,0,0,-4294967296,"
            "?,0,"
            "?,1,?,?,"
            "NULL,NULL,NULL,NULL,?)",
            -1, &ins, NULL) == SQLITE_OK) {
            sqlite3_bind_int(ins, 1, nPK);      /* Z_PK */
            sqlite3_bind_int(ins, 2, intId);     /* ZINTEGERID */
            sqlite3_bind_int(ins, 3, bPK);       /* ZBODY */
            sqlite3_bind_double(ins, 4, now);    /* ZCREATIONDATE */
            sqlite3_bind_double(ins, 5, now);    /* ZMODIFICATIONDATE */
            sqlite3_bind_text(ins, 6, [title UTF8String], -1, SQLITE_TRANSIENT); /* ZTITLE */
            rc = sqlite3_step(ins);
            sqlite3_finalize(ins);
        }

        /* Update ALL counters */
        sqlite3_exec(db, [[NSString stringWithFormat:
            @"UPDATE Z_PRIMARYKEY SET Z_MAX=%d WHERE Z_NAME='Note'", nPK] UTF8String], NULL, NULL, NULL);
        sqlite3_exec(db, [[NSString stringWithFormat:
            @"UPDATE Z_PRIMARYKEY SET Z_MAX=%d WHERE Z_NAME='NoteBody'", bPK] UTF8String], NULL, NULL, NULL);
        /* Update the REAL counter in ZNEXTID */
        sqlite3_exec(db, [[NSString stringWithFormat:
            @"UPDATE ZNEXTID SET ZCOUNTER=%d WHERE Z_PK=1", intId] UTF8String], NULL, NULL, NULL);

        sqlite3_close(db);

        /* Delete the index cache and kill Notes.app so it rebuilds from DB */
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Notes/notes.idx" error:nil];
        FILE *fp = popen("killall MobileNotes 2>/dev/null", "r");
        if (fp) pclose(fp);

        cb([NSString stringWithFormat:@"Note '%@' created.", title], nil);
    }; return t;
}

+ (OCToolDefinition *)listNotesTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_notes"; t.toolDescription = @"List notes from iOS Notes app";
    t.inputSchema = @{@"type": @"object", @"properties": @{}};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { cb(@"Cannot open Notes DB", nil); return; }
        NSMutableArray *r = [NSMutableArray array]; sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "SELECT Z_PK,ZTITLE,ZSUMMARY FROM ZNOTE WHERE ZDELETEDFLAG=0 ORDER BY ZMODIFICATIONDATE DESC LIMIT 20", -1, &s, NULL)==SQLITE_OK) {
            while (sqlite3_step(s)==SQLITE_ROW) { [r addObject:[NSString stringWithFormat:@"[%d] %s", sqlite3_column_int(s,0), sqlite3_column_text(s,1)?:(const unsigned char *)"(untitled)"]]; } sqlite3_finalize(s); }
        sqlite3_close(db);
        cb([r count]>0?[r componentsJoinedByString:@"\n"]:@"No notes", nil);
    }; return t;
}

+ (OCToolDefinition *)readNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"read_note"; t.toolDescription = @"Read a note from iOS Notes app by ID";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        NSString *result = @"Not found"; sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "SELECT n.ZTITLE,b.ZCONTENT FROM ZNOTE n JOIN ZNOTEBODY b ON n.ZBODY=b.Z_PK WHERE n.Z_PK=?", -1, &s, NULL)==SQLITE_OK) {
            sqlite3_bind_int(s,1,[[p objectForKey:@"id"] intValue]);
            if (sqlite3_step(s)==SQLITE_ROW) {
                NSString *html = sqlite3_column_text(s,1)?[NSString stringWithUTF8String:(const char*)sqlite3_column_text(s,1)]:@"";
                NSMutableString *plain = [html mutableCopy];
                while (YES) { NSRange r = [plain rangeOfString:@"<[^>]+>" options:NSRegularExpressionSearch]; if (r.location==NSNotFound) break; [plain deleteCharactersInRange:r]; }
                result = [NSString stringWithFormat:@"%s\n\n%@", sqlite3_column_text(s,0)?:(const unsigned char *)"", plain]; [plain release];
            } sqlite3_finalize(s); }
        sqlite3_close(db); cb(result, nil);
    }; return t;
}

+ (OCToolDefinition *)updateNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"update_note"; t.toolDescription = @"Update a note in iOS Notes app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"id": @{@"type": @"integer"}, @"title": @{@"type": @"string"}, @"content": @{@"type": @"string"}}, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        int nid = [[p objectForKey:@"id"] intValue]; double now = [[NSDate date] timeIntervalSinceReferenceDate];
        if ([p objectForKey:@"title"]) { sqlite3_stmt *s; if (sqlite3_prepare_v2(db,"UPDATE ZNOTE SET ZTITLE=?,ZMODIFICATIONDATE=? WHERE Z_PK=?",-1,&s,NULL)==SQLITE_OK) { sqlite3_bind_text(s,1,[[p objectForKey:@"title"] UTF8String],-1,SQLITE_TRANSIENT); sqlite3_bind_double(s,2,now); sqlite3_bind_int(s,3,nid); sqlite3_step(s); sqlite3_finalize(s); } }
        if ([p objectForKey:@"content"]) { NSString *html = [NSString stringWithFormat:@"<html><body><div>%@</div></body></html>", [p objectForKey:@"content"]]; sqlite3_stmt *s; if (sqlite3_prepare_v2(db,"UPDATE ZNOTEBODY SET ZCONTENT=? WHERE ZOWNER=?",-1,&s,NULL)==SQLITE_OK) { sqlite3_bind_text(s,1,[html UTF8String],-1,SQLITE_TRANSIENT); sqlite3_bind_int(s,2,nid); sqlite3_step(s); sqlite3_finalize(s); } }
        sqlite3_close(db); cb(@"Note updated", nil);
    }; return t;
}

+ (OCToolDefinition *)deleteNoteTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"delete_note"; t.toolDescription = @"Delete a note from iOS Notes app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        sqlite3_exec(db,[[NSString stringWithFormat:@"UPDATE ZNOTE SET ZDELETEDFLAG=1 WHERE Z_PK=%d",[[p objectForKey:@"id"] intValue]] UTF8String],NULL,NULL,NULL);
        sqlite3_close(db); cb(@"Note deleted", nil);
    }; return t;
}

+ (OCToolDefinition *)searchNotesTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"search_notes"; t.toolDescription = @"Search notes by keyword";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"query": @{@"type": @"string"}}, @"required": @[@"query"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([NOTES_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        NSMutableArray *r = [NSMutableArray array]; sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "SELECT n.Z_PK,n.ZTITLE FROM ZNOTE n JOIN ZNOTEBODY b ON n.ZBODY=b.Z_PK WHERE n.ZDELETEDFLAG=0 AND (n.ZTITLE LIKE ? OR b.ZCONTENT LIKE ?) LIMIT 10", -1, &s, NULL)==SQLITE_OK) {
            NSString *q = [NSString stringWithFormat:@"%%%@%%", [p objectForKey:@"query"]];
            sqlite3_bind_text(s,1,[q UTF8String],-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,2,[q UTF8String],-1,SQLITE_TRANSIENT);
            while (sqlite3_step(s)==SQLITE_ROW) [r addObject:[NSString stringWithFormat:@"[%d] %s", sqlite3_column_int(s,0), sqlite3_column_text(s,1)?:(const unsigned char *)""]];
            sqlite3_finalize(s); }
        sqlite3_close(db); cb([r count]>0?[r componentsJoinedByString:@"\n"]:@"No matches", nil);
    }; return t;
}

#pragma mark - Reminders

+ (OCToolDefinition *)createReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"create_reminder"; t.toolDescription = @"Create a reminder visible in iOS Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"title": @{@"type": @"string"}, @"due_date": @{@"type": @"string", @"description": @"YYYY-MM-DD or YYYY-MM-DD HH:MM"}, @"priority": @{@"type": @"integer"}, @"notes": @{@"type": @"string"}, @"list_id": @{@"type": @"integer", @"description": @"Calendar/list ID. Default 5 = Reminders. Use list_reminder_lists to see available lists."}}, @"required": @[@"title"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open Calendar DB", nil); return; }
        double dueDate = 0; NSString *ds = [p objectForKey:@"due_date"];
        if (ds) { NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"yyyy-MM-dd HH:mm"]; NSDate *d=[f dateFromString:ds]; if(!d){[f setDateFormat:@"yyyy-MM-dd"];d=[f dateFromString:ds];} if(d) dueDate=[d timeIntervalSinceReferenceDate]; }
        CFUUIDRef u = CFUUIDCreate(NULL); NSString *uuid = [(NSString *)CFUUIDCreateString(NULL,u) autorelease]; CFRelease(u);
        double now = [[NSDate date] timeIntervalSinceReferenceDate];
        int listId = [[p objectForKey:@"list_id"] intValue];
        if (listId <= 0) listId = 5; /* Default Reminders list */
        sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "INSERT INTO CalendarItem (summary,description,calendar_id,entity_type,priority,due_date,creation_date,last_modified,UUID,status,hidden) VALUES (?,?,?,3,?,?,?,?,?,0,0)", -1, &s, NULL)==SQLITE_OK) {
            sqlite3_bind_text(s,1,[[p objectForKey:@"title"] UTF8String],-1,SQLITE_TRANSIENT);
            sqlite3_bind_text(s,2,[[p objectForKey:@"notes"]?:@"" UTF8String],-1,SQLITE_TRANSIENT);
            sqlite3_bind_int(s,3,listId);  /* calendar_id */
            sqlite3_bind_int(s,4,[[p objectForKey:@"priority"] intValue]);
            if(dueDate>0) sqlite3_bind_double(s,5,dueDate); else sqlite3_bind_null(s,5);
            sqlite3_bind_double(s,6,now); sqlite3_bind_double(s,7,now);
            sqlite3_bind_text(s,8,[uuid UTF8String],-1,SQLITE_TRANSIENT);
            sqlite3_step(s); sqlite3_finalize(s); }
        sqlite3_close(db);
        /* Kill Reminders so it reloads from DB */
        FILE *fp = popen("killall Reminders 2>/dev/null", "r"); if(fp) pclose(fp);
        cb([NSString stringWithFormat:@"Reminder '%@' created.", [p objectForKey:@"title"]], nil);
    }; return t;
}

+ (OCToolDefinition *)listRemindersTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_reminders"; t.toolDescription = @"List reminders from iOS Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"show_completed": @{@"type": @"boolean"}}, @"required": @[]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        BOOL all = [[p objectForKey:@"show_completed"] boolValue];
        NSString *sql = all ? @"SELECT ROWID,summary,due_date,completion_date FROM CalendarItem WHERE entity_type=3 ORDER BY creation_date DESC LIMIT 20"
            : @"SELECT ROWID,summary,due_date,completion_date FROM CalendarItem WHERE entity_type=3 AND completion_date IS NULL ORDER BY creation_date DESC LIMIT 20";
        NSMutableArray *r = [NSMutableArray array]; sqlite3_stmt *s;
        NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease]; [f setDateFormat:@"yyyy-MM-dd HH:mm"];
        if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &s, NULL)==SQLITE_OK) {
            while (sqlite3_step(s)==SQLITE_ROW) {
                BOOL done = sqlite3_column_type(s,3)!=SQLITE_NULL;
                NSString *due = @"";
                if (sqlite3_column_type(s,2)!=SQLITE_NULL) due = [NSString stringWithFormat:@" (due: %@)", [f stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(s,2)]]];
                [r addObject:[NSString stringWithFormat:@"%@ [%d] %s%@", done?@"[x]":@"[ ]", sqlite3_column_int(s,0), sqlite3_column_text(s,1)?:(const unsigned char *)"", due]];
            } sqlite3_finalize(s); }
        sqlite3_close(db); cb([r count]>0?[r componentsJoinedByString:@"\n"]:@"No reminders", nil);
    }; return t;
}

+ (OCToolDefinition *)completeReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"complete_reminder"; t.toolDescription = @"Complete a reminder in iOS Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        double now = [[NSDate date] timeIntervalSinceReferenceDate];
        sqlite3_exec(db,[[NSString stringWithFormat:@"UPDATE CalendarItem SET completion_date=%f,last_modified=%f WHERE ROWID=%d",now,now,[[p objectForKey:@"id"] intValue]] UTF8String],NULL,NULL,NULL);
        sqlite3_close(db); cb(@"Reminder completed", nil);
    }; return t;
}

+ (OCToolDefinition *)deleteReminderTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"delete_reminder"; t.toolDescription = @"Delete a reminder from iOS Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"id": @{@"type": @"integer"}}, @"required": @[@"id"]};
    t.requiresConfirmation = YES;
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        sqlite3_exec(db,[[NSString stringWithFormat:@"DELETE FROM CalendarItem WHERE ROWID=%d AND entity_type=3",[[p objectForKey:@"id"] intValue]] UTF8String],NULL,NULL,NULL);
        sqlite3_close(db);
        FILE *fp = popen("killall Reminders 2>/dev/null", "r"); if(fp) pclose(fp);
        cb(@"Reminder deleted", nil);
    }; return t;
}

+ (OCToolDefinition *)listReminderListsTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"list_reminder_lists"; t.toolDescription = @"List all reminder lists (calendars) in Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{}};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        NSMutableArray *r = [NSMutableArray array]; sqlite3_stmt *s;
        /* supported_entity_types & 8 = has reminders */
        if (sqlite3_prepare_v2(db, "SELECT ROWID, title, supported_entity_types FROM Calendar WHERE supported_entity_types & 8 OR ROWID=5", -1, &s, NULL)==SQLITE_OK) {
            while (sqlite3_step(s)==SQLITE_ROW) {
                int rid = sqlite3_column_int(s,0);
                const char *title = (const char *)sqlite3_column_text(s,1);
                NSString *name = title ? [NSString stringWithUTF8String:title] : @"(unnamed)";
                if ([name isEqualToString:@"DEFAULT_TASK_CALENDAR_NAME"]) name = @"Reminders";
                [r addObject:[NSString stringWithFormat:@"[%d] %@", rid, name]];
            } sqlite3_finalize(s); }
        sqlite3_close(db);
        cb([r count]>0?[r componentsJoinedByString:@"\n"]:@"No lists", nil);
    }; return t;
}

+ (OCToolDefinition *)createReminderListTool {
    OCToolDefinition *t = [[[OCToolDefinition alloc] init] autorelease];
    t.name = @"create_reminder_list"; t.toolDescription = @"Create a new reminder list in Reminders app";
    t.inputSchema = @{@"type": @"object", @"properties": @{@"name": @{@"type": @"string"}}, @"required": @[@"name"]};
    t.handler = ^(NSDictionary *p, OCToolResultBlock cb) {
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([CALENDAR_DB UTF8String], &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) { cb(@"Cannot open", nil); return; }
        CFUUIDRef u = CFUUIDCreate(NULL); NSString *uuid = [(NSString *)CFUUIDCreateString(NULL,u) autorelease]; CFRelease(u);
        sqlite3_stmt *s;
        if (sqlite3_prepare_v2(db, "INSERT INTO Calendar (store_id,title,flags,supported_entity_types,UUID) VALUES (1,?,0,8,?)", -1, &s, NULL)==SQLITE_OK) {
            sqlite3_bind_text(s,1,[[p objectForKey:@"name"] UTF8String],-1,SQLITE_TRANSIENT);
            sqlite3_bind_text(s,2,[uuid UTF8String],-1,SQLITE_TRANSIENT);
            sqlite3_step(s); sqlite3_finalize(s);
        }
        int newId = (int)sqlite3_last_insert_rowid(db);
        sqlite3_close(db);
        FILE *fp = popen("killall Reminders 2>/dev/null", "r"); if(fp) pclose(fp);
        cb([NSString stringWithFormat:@"List '%@' created (ID:%d).", [p objectForKey:@"name"], newId], nil);
    }; return t;
}

@end
