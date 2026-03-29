/*
 * OCGuardrails.h
 * LegacyPodClaw - Safety Guardrails System
 *
 * Prevents the AI from breaking iOS. Validates all filesystem paths,
 * shell commands, and database operations before execution.
 * All checks are synchronous and cheap (string matching only).
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, OCGuardrailAction) {
    OCGuardrailAllow = 0,
    OCGuardrailConfirm,     /* Needs user confirmation */
    OCGuardrailBlock         /* Hard block, never allow */
};

@interface OCGuardrailVerdict : NSObject
@property (nonatomic, assign) OCGuardrailAction action;
@property (nonatomic, copy) NSString *reason;
+ (OCGuardrailVerdict *)allow;
+ (OCGuardrailVerdict *)confirmWithReason:(NSString *)reason;
+ (OCGuardrailVerdict *)blockWithReason:(NSString *)reason;
@end

typedef NS_ENUM(NSUInteger, OCFileOp) {
    OCFileOpRead = 0,
    OCFileOpWrite,
    OCFileOpEdit,
    OCFileOpDelete
};

@interface OCGuardrails : NSObject

+ (instancetype)shared;

/* Check a filesystem path before an operation */
- (OCGuardrailVerdict *)checkPath:(NSString *)path forOperation:(OCFileOp)op;

/* Check a shell command before execution */
- (OCGuardrailVerdict *)checkCommand:(NSString *)command;

/* Check an SMS database query */
- (OCGuardrailVerdict *)checkSQLQuery:(NSString *)query onDatabase:(NSString *)dbPath;

/* Check disk space — returns NO if below 50MB free */
- (BOOL)hasSufficientDiskSpace;
- (NSUInteger)freeDiskSpaceMB;

/* Rate limiting */
- (BOOL)allowBashExecution;   /* Max 10/min */
- (BOOL)allowFileWrite;       /* Max 5/min */
- (BOOL)allowSMSInsert;       /* Max 1/5sec */

/* Max file write size in bytes (1MB) */
@property (nonatomic, readonly) NSUInteger maxFileWriteSize;

@end
