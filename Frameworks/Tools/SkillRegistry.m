/*
 * OCSkillRegistry.m
 * LegacyPodClaw - Skills System Implementation
 */

#import "SkillRegistry.h"
#import "Agent.h"

@implementation OCSkill
- (void)dealloc {
    [_skillId release]; [_skillName release]; [_skillDescription release];
    [_systemPromptFragment release]; [_activationKeywords release];
    [super dealloc];
}
@end

@interface OCSkillRegistry () {
    NSMutableDictionary *_skills;
    NSString *_basePrompt;
    NSString *_activeSkillId;
}
@end

@implementation OCSkillRegistry

+ (instancetype)shared {
    static OCSkillRegistry *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _skills = [[NSMutableDictionary alloc] initWithCapacity:8];
        [self _registerBuiltinSkills];
        [self _buildBasePrompt];
    }
    return self;
}

- (void)dealloc { [_skills release]; [_basePrompt release]; [_activeSkillId release]; [super dealloc]; }

- (NSString *)baseSystemPrompt { return _basePrompt; }
- (NSArray *)allSkills { return [_skills allValues]; }
- (OCSkill *)skillForId:(NSString *)sid { return [_skills objectForKey:sid]; }

- (void)activateSkill:(NSString *)skillId onAgent:(OCAgent *)agent {
    OCSkill *skill = [_skills objectForKey:skillId];
    if (!skill) return;
    [_activeSkillId release];
    _activeSkillId = [skillId copy];
    NSString *composed = [NSString stringWithFormat:@"%@\n\n---\nACTIVE SKILL: %@\n%@\n---",
        _basePrompt, skill.skillName, skill.systemPromptFragment];
    agent.systemPrompt = composed;
}

- (void)deactivateAllSkillsOnAgent:(OCAgent *)agent {
    [_activeSkillId release]; _activeSkillId = nil;
    agent.systemPrompt = _basePrompt;
}

- (NSArray *)detectSkillsForMessage:(NSString *)message {
    NSString *lower = [message lowercaseString];
    NSMutableArray *matches = [NSMutableArray array];
    for (OCSkill *skill in [_skills allValues]) {
        for (NSString *kw in skill.activationKeywords) {
            if ([lower rangeOfString:kw].location != NSNotFound) {
                [matches addObject:skill];
                break;
            }
        }
    }
    return matches;
}

#pragma mark - Base System Prompt

- (void)_buildBasePrompt {
    _basePrompt = [@"You are LegacyPodClaw (Molty), an AI assistant on a jailbroken iOS 6 device.\n\n"
    "DEVICE: iOS 6 ARMv7 (iPod Touch 4/iPhone 3GS/4/4S/iPad 2/3/mini), constrained RAM (80MB budget).\n\n"
    "SAFETY RULES (enforced by guardrails - violations auto-blocked):\n"
    "1. NEVER modify /System, /sbin, /bin, /usr/lib, /usr/libexec, /boot, /var/stash\n"
    "2. NEVER rm -rf on root/system dirs\n"
    "3. NEVER modify kernel, bootloader, or baseband\n"
    "4. SMS database: only INSERT into LegacyPodClaw chat thread, never DELETE others\n"
    "5. NEVER disable MobileSubstrate (causes boot loop)\n"
    "6. Check disk space before large writes. Max write: 1MB. Max bash: 30s.\n"
    "7. Destructive ops (kill, respring, reboot, pkg removal) need user confirmation.\n"
    "8. NEVER access /var/Keychains or credential files.\n\n"
    "SKILLS (activate by context or user request):\n"
    "- /theos - Jailbreak tweak development\n"
    "- /headers - iOS 6 private headers reference\n"
    "- /cydia - Cydia package publishing\n"
    "- /sysadmin - System administration\n"
    "- /files - File management\n"
    "- /network - Network diagnostics\n\n"
    "Be concise. This device has limited resources." copy];
}

#pragma mark - Builtin Skills

- (void)_registerBuiltinSkills {
    /* Theos Development */
    OCSkill *theos = [[OCSkill alloc] init];
    theos.skillId = @"theos";
    theos.skillName = @"Theos Tweak Development";
    theos.skillDescription = @"Develop jailbreak tweaks with Theos + Logos";
    theos.activationKeywords = @[@"tweak", @"theos", @"hook", @"substrate", @"logos", @".xm", @"jailbreak dev"];
    theos.systemPromptFragment =
        @"Expert iOS 6 jailbreak developer using Theos.\n"
        "- Target: ARMv7, iOS 6.0-6.1.6, clang\n"
        "- Theos at $THEOS (~/theos on Mac, /var/theos on device)\n"
        "- Logos: %hook/%end/%orig/%new/%init/%group in .xm files\n"
        "- NIC templates: iphone/tweak, iphone/application, iphone/preference_bundle\n"
        "- Build: make package. Install: make package install THEOS_DEVICE_IP=<ip>\n"
        "- iOS 6 Headers at ~/iOS-6-Headers/SpringBoard/\n"
        "- Key classes: SpringBoard, SBUIController, SBAwayController, SBIconController\n"
        "- MobileSubstrate filter .plist: {Filter:{Bundles:[com.apple.springboard]}}\n"
        "- PreferenceBundle: subclass PSListController, load specifiers from Root.plist\n"
        "- Debug: NSLog + syslog. ldid for signing. dpkg-deb for packaging.\n"
        "- MRR (manual retain/release) for memory efficiency on 256MB device.\n"
        "When creating a tweak: generate Makefile, control, Tweak.xm, filter .plist.";
    [_skills setObject:theos forKey:@"theos"];
    [theos release];

    /* iOS 6 Headers */
    OCSkill *headers = [[OCSkill alloc] init];
    headers.skillId = @"headers";
    headers.skillName = @"iOS 6 Headers Reference";
    headers.skillDescription = @"Reference class-dumped iOS 6 private headers";
    headers.activationKeywords = @[@"header", @"class-dump", @"private api", @"sbui", @"springboard class"];
    headers.systemPromptFragment =
        @"iOS 6 private headers at ~/iOS-6-Headers/SpringBoard/ (509 headers).\n"
        "Key classes:\n"
        "- SpringBoard.h: menuButtonDown/Up, _menuButtonWasHeld, _menuHoldTime\n"
        "- SBUIController.h: clickedMenuButton, handleMenuDoubleTap, activateSwitcher\n"
        "- SBAwayController.h: lock screen, handleCameraPanGesture, unlockWithSound\n"
        "- SBAwayView.h: _dateHeaderView ivar, layoutSubviews\n"
        "- SBBulletinListController.h: _loadSections, _weeApps, _visibleWeeApps\n"
        "- SBNowPlayingBar.h: views (app switcher pages)\n"
        "- SBVoiceControlController.h: handleHomeButtonHeld\n"
        "- SBMediaController.h: nowPlayingTitle, togglePlayPause, volume\n"
        "- SBIconModel.h: applicationIconForDisplayIdentifier:\n"
        "- SBApplication.h: displayIdentifier, isRunning\n"
        "- BBWeeAppController-Protocol.h: NC widget protocol (view, viewHeight)\n\n"
        "NO NSURLSession (iOS 7+). NO UICollectionView. NO Auto Layout.\n"
        "Use NSURLConnection, UITableView, autoresizingMask/frames.\n"
        "Use grep/read_file on ~/iOS-6-Headers/ to find exact method signatures.";
    [_skills setObject:headers forKey:@"headers"];
    [headers release];

    /* Cydia Publishing */
    OCSkill *cydia = [[OCSkill alloc] init];
    cydia.skillId = @"cydia";
    cydia.skillName = @"Cydia Package Publishing";
    cydia.skillDescription = @"Build and publish Cydia packages and repos";
    cydia.activationKeywords = @[@"cydia", @"publish", @"repo", @"deb", @"package", @"dpkg"];
    cydia.systemPromptFragment =
        @"Cydia package publishing:\n"
        "- Format: .deb (Debian) for iphoneos-arm\n"
        "- control file: Package, Name, Depends, Version, Architecture, Description, Author, Section\n"
        "- Sections: Tweaks, Utilities, Themes, System\n"
        "- Common deps: firmware (>= 6.0), mobilesubstrate, preferenceloader\n"
        "- Build: make package (Theos) or dpkg-deb -b ./pkg output.deb\n"
        "- Host repo: static HTTP with /deb/*.deb, /Packages.bz2, /Release, /CydiaIcon.png\n"
        "- Generate index: dpkg-scanpackages . /dev/null > Packages && bzip2 Packages\n"
        "- BigBoss submission: email .deb to admin@thebigboss.org\n"
        "- Depiction: HTML URL in control file\n"
        "- Version: semver. Cydia shows upgrade badge on bump.";
    [_skills setObject:cydia forKey:@"cydia"];
    [cydia release];

    /* Sysadmin */
    OCSkill *sysadmin = [[OCSkill alloc] init];
    sysadmin.skillId = @"sysadmin";
    sysadmin.skillName = @"System Administration";
    sysadmin.skillDescription = @"iOS 6 system administration and diagnostics";
    sysadmin.activationKeywords = @[@"sysadmin", @"system", @"process", @"daemon", @"launchctl", @"dpkg", @"log", @"crash"];
    sysadmin.systemPromptFragment =
        @"Administering jailbroken iPod Touch 4 (iOS 6.1.6).\n"
        "Paths: /Applications/ (system apps), /var/mobile/Applications/ (sandboxed),\n"
        "  /Library/MobileSubstrate/DynamicLibraries/ (tweaks), /var/log/syslog,\n"
        "  /var/mobile/Library/Logs/CrashReporter/, /var/mobile/Library/Caches/\n"
        "Commands: dpkg -l, dpkg -L <pkg>, plutil, killall SpringBoard (respring),\n"
        "  launchctl list, df -h, du -sh, find, grep\n"
        "GUARDRAIL: Cannot modify /System, /sbin, /bin, /usr/lib, /boot.";
    [_skills setObject:sysadmin forKey:@"sysadmin"];
    [sysadmin release];

    /* File Manager */
    OCSkill *files = [[OCSkill alloc] init];
    files.skillId = @"files";
    files.skillName = @"File Management";
    files.skillDescription = @"Browse, edit, and manage files on the device";
    files.activationKeywords = @[@"file", @"directory", @"folder", @"plist", @"edit file", @"find file"];
    files.systemPromptFragment =
        @"File manager for iOS 6. Tools: list_files, read_file, write_file, edit_file, delete_file, bash.\n"
        "- plutil -convert xml1 <file> to make plists readable\n"
        "- file <path> to identify type. sips for images.\n"
        "- sqlite3 for .db files (if available)\n"
        "- tar, gzip, bzip2 for archives\n"
        "GUARDRAIL: Protected paths enforced. Cannot write to /System, /usr/lib, etc.";
    [_skills setObject:files forKey:@"files"];
    [files release];

    /* Network */
    OCSkill *network = [[OCSkill alloc] init];
    network.skillId = @"network";
    network.skillName = @"Network Diagnostics";
    network.skillDescription = @"Network troubleshooting and diagnostics";
    network.activationKeywords = @[@"network", @"wifi", @"ping", @"dns", @"ip address", @"port", @"ssh"];
    network.systemPromptFragment =
        @"Network diagnostics (iPod Touch 4 = WiFi only).\n"
        "- Interfaces: en0 (WiFi), lo0 (loopback)\n"
        "- ping -c 3 <host>, netstat -an, arp -a, netstat -rn\n"
        "- DNS: cat /etc/resolv.conf\n"
        "- nc -z <host> <port> for port scan\n"
        "- OpenSSH on port 22 (default pw: alpine - remind user to change!)\n"
        "- Use network_info tool for interface list\n"
        "- Use http_fetch tool for HTTP testing";
    [_skills setObject:network forKey:@"network"];
    [network release];
}

@end
