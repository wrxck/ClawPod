/*
 * OCSkillRegistry.h
 * LegacyPodClaw - Built-in Skills System
 *
 * Skills are contextual prompt + tool configurations that activate
 * when the user's request matches. Each skill adds a system prompt
 * fragment and optional specialized tools.
 */

#import <Foundation/Foundation.h>

@class OCAgent;

@interface OCSkill : NSObject
@property (nonatomic, copy) NSString *skillId;
@property (nonatomic, copy) NSString *skillName;
@property (nonatomic, copy) NSString *skillDescription;
@property (nonatomic, copy) NSString *systemPromptFragment;
@property (nonatomic, copy) NSArray *activationKeywords;
@end

@interface OCSkillRegistry : NSObject

+ (instancetype)shared;
- (NSArray *)allSkills;
- (OCSkill *)skillForId:(NSString *)skillId;
- (void)activateSkill:(NSString *)skillId onAgent:(OCAgent *)agent;
- (void)deactivateAllSkillsOnAgent:(OCAgent *)agent;
- (NSArray *)detectSkillsForMessage:(NSString *)message;
- (NSString *)baseSystemPrompt;

@end
