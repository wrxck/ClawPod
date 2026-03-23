/*
 * CPLauncher.m
 * ClawPod - Agentic Home Screen Launcher Implementation
 *
 * A conversation-first home screen. The user types what they want
 * to do and ClawPod finds/launches the right app or performs the action.
 * Suggested apps appear based on time of day and usage patterns.
 */

#import "CPLauncher.h"
#import <notify.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"
#define LAUNCHER_BG [UIColor colorWithRed:0.06f green:0.06f blue:0.10f alpha:1.0f]

/* Forward declarations for SpringBoard private classes */
@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (id)allApplications;
- (id)applicationWithDisplayIdentifier:(id)displayId;
@end

@interface SBApplication : NSObject
- (NSString *)displayIdentifier;
- (NSString *)displayName;
- (id)pathForIcon;
@end

@interface SBUIController : NSObject
+ (id)sharedInstance;
- (void)activateApplicationAnimated:(id)app;
@end

BOOL CPLauncherIsEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    return [[prefs objectForKey:@"launcherEnabled"] boolValue];
}

@interface CPLauncher () {
    /* Header */
    UILabel *_greeting;
    UILabel *_dateLabel;

    /* Search / command bar */
    UITextField *_commandField;

    /* Suggested apps */
    UIScrollView *_suggestedScroll;
    NSArray *_suggestedApps;

    /* Quick actions */
    UIScrollView *_actionsScroll;

    /* Recent / AI feed */
    UITableView *_feedTable;
    NSMutableArray *_feedItems;

    /* Status bar at bottom */
    UIView *_statusBar;
    UILabel *_statusLabel;

    /* All installed apps (for search) */
    NSArray *_allApps;

    /* Search results */
    NSArray *_searchResults;
    BOOL _isSearching;
}
@end

@implementation CPLauncher

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = LAUNCHER_BG;
        _feedItems = [[NSMutableArray alloc] initWithCapacity:10];
        _isActive = NO;
        [self _buildUI];
    }
    return self;
}

- (void)dealloc {
    [_greeting release]; [_dateLabel release]; [_commandField release];
    [_suggestedScroll release]; [_suggestedApps release]; [_actionsScroll release];
    [_feedTable release]; [_feedItems release]; [_statusBar release]; [_statusLabel release];
    [_allApps release]; [_searchResults release];
    [super dealloc];
}

#pragma mark - Build UI

- (void)_buildUI {
    CGFloat w = self.bounds.size.width;
    CGFloat y = 24; /* Below status bar */

    /* Greeting */
    _greeting = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    _greeting.font = [UIFont boldSystemFontOfSize:24];
    _greeting.textColor = [UIColor whiteColor];
    _greeting.backgroundColor = [UIColor clearColor];
    [self addSubview:_greeting];
    y += 30;

    /* Date */
    _dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 16)];
    _dateLabel.font = [UIFont systemFontOfSize:13];
    _dateLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1];
    _dateLabel.backgroundColor = [UIColor clearColor];
    [self addSubview:_dateLabel];
    y += 24;

    /* Command bar */
    _commandField = [[UITextField alloc] initWithFrame:CGRectMake(12, y, w - 24, 38)];
    _commandField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08f];
    _commandField.textColor = [UIColor whiteColor];
    _commandField.font = [UIFont systemFontOfSize:15];
    _commandField.layer.cornerRadius = 19;
    _commandField.layer.masksToBounds = YES;
    _commandField.placeholder = @"What do you want to do?";
    _commandField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _commandField.delegate = self;
    _commandField.returnKeyType = UIReturnKeyGo;
    UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 38)] autorelease];
    _commandField.leftView = pad;
    _commandField.leftViewMode = UITextFieldViewModeAlways;
    [self addSubview:_commandField];
    y += 48;

    /* Suggested apps section */
    UILabel *sugLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 16)] autorelease];
    sugLabel.text = @"SUGGESTED";
    sugLabel.font = [UIFont boldSystemFontOfSize:10];
    sugLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1];
    sugLabel.backgroundColor = [UIColor clearColor];
    [self addSubview:sugLabel];
    y += 20;

    _suggestedScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, w, 76)];
    _suggestedScroll.showsHorizontalScrollIndicator = NO;
    _suggestedScroll.backgroundColor = [UIColor clearColor];
    [self addSubview:_suggestedScroll];
    y += 82;

    /* Quick actions */
    UILabel *actLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 16)] autorelease];
    actLabel.text = @"QUICK ACTIONS";
    actLabel.font = [UIFont boldSystemFontOfSize:10];
    actLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1];
    actLabel.backgroundColor = [UIColor clearColor];
    [self addSubview:actLabel];
    y += 20;

    _actionsScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, w, 36)];
    _actionsScroll.showsHorizontalScrollIndicator = NO;
    _actionsScroll.backgroundColor = [UIColor clearColor];
    [self _buildQuickActions];
    [self addSubview:_actionsScroll];
    y += 42;

    /* Feed / recent */
    UILabel *feedLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 16)] autorelease];
    feedLabel.text = @"FEED";
    feedLabel.font = [UIFont boldSystemFontOfSize:10];
    feedLabel.textColor = [UIColor colorWithWhite:0.45f alpha:1];
    feedLabel.backgroundColor = [UIColor clearColor];
    [self addSubview:feedLabel];
    y += 20;

    CGFloat remaining = self.bounds.size.height - y - 30; /* Leave space for status bar */
    _feedTable = [[UITableView alloc] initWithFrame:CGRectMake(0, y, w, remaining)
                                              style:UITableViewStylePlain];
    _feedTable.dataSource = self;
    _feedTable.delegate = self;
    _feedTable.backgroundColor = [UIColor clearColor];
    _feedTable.separatorColor = [UIColor colorWithWhite:0.15f alpha:1];
    [self addSubview:_feedTable];

    /* Bottom status bar */
    _statusBar = [[UIView alloc] initWithFrame:
        CGRectMake(0, self.bounds.size.height - 28, w, 28)];
    _statusBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, w - 24, 20)];
    _statusLabel.font = [UIFont systemFontOfSize:10];
    _statusLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1];
    _statusLabel.backgroundColor = [UIColor clearColor];
    [_statusBar addSubview:_statusLabel];
    [self addSubview:_statusBar];

    /* Tap to dismiss keyboard */
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(_dismissKB)];
    tap.cancelsTouchesInView = NO;
    [_feedTable addGestureRecognizer:tap];
    [tap release];
}

- (void)_buildQuickActions {
    CGFloat w = self.bounds.size.width;
    NSArray *actions = @[@"Ask AI", @"Settings", @"Messages", @"Safari", @"Music", @"Photos"];
    CGFloat x = 12;
    for (NSString *title in actions) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat btnW = [title length] * 8 + 24;
        btn.frame = CGRectMake(x, 0, btnW, 32);
        btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1f];
        btn.layer.cornerRadius = 16;
        [btn setTitle:title forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12];
        [btn addTarget:self action:@selector(_actionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_actionsScroll addSubview:btn];
        x += btnW + 8;
    }
    _actionsScroll.contentSize = CGSizeMake(x, 36);
}

#pragma mark - Activate / Deactivate

- (void)activate {
    _isActive = YES;
    [self refresh];
    self.hidden = NO;
    self.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }];
}

- (void)deactivate {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0;
    } completion:^(BOOL f) {
        self.hidden = YES;
        _isActive = NO;
    }];
}

#pragma mark - Refresh

- (void)refresh {
    /* Greeting based on time of day */
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal components:NSHourCalendarUnit fromDate:[NSDate date]].hour;
    if (hour < 12) _greeting.text = @"Good morning";
    else if (hour < 17) _greeting.text = @"Good afternoon";
    else _greeting.text = @"Good evening";

    /* Date */
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    [fmt setDateFormat:@"EEEE, MMMM d"];
    _dateLabel.text = [fmt stringFromDate:[NSDate date]];

    /* Load all apps */
    [self _loadApps];

    /* Build suggested apps (time-based suggestions) */
    [self _buildSuggestedApps];

    /* Build feed items */
    [self _buildFeed];

    /* Status */
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *host = [prefs objectForKey:@"gatewayHost"];
    BOOL hasKey = [[prefs objectForKey:@"apiKey"] length] > 0;
    BOOL daemonRunning = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/run/clawpodd.pid"];

    NSMutableString *status = [NSMutableString stringWithString:@"ClawPod v0.1.0"];
    if (host) [status appendFormat:@" | Gateway: %@", host];
    else if (hasKey) [status appendString:@" | Direct API"];
    if (daemonRunning) [status appendString:@" | Daemon: Running"];
    _statusLabel.text = status;
}

- (void)_loadApps {
    @try {
        id appController = [NSClassFromString(@"SBApplicationController") sharedInstance];
        if (appController) {
            [_allApps release];
            _allApps = [[appController allApplications] retain];
        }
    } @catch (NSException *e) {}
}

- (void)_buildSuggestedApps {
    /* Time-based app suggestions */
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal components:NSHourCalendarUnit fromDate:[NSDate date]].hour;

    NSMutableArray *suggested = [NSMutableArray arrayWithCapacity:6];

    /* Morning: Mail, Weather, Calendar */
    /* Afternoon: Safari, Messages */
    /* Evening: Music, Photos, YouTube */
    NSArray *morningApps = @[@"com.apple.mobilemail", @"com.apple.mobilecal",
                              @"com.apple.mobilesafari", @"com.apple.MobileSMS"];
    NSArray *eveningApps = @[@"com.apple.Music", @"com.apple.mobileslideshow",
                              @"com.google.ios.youtube", @"com.apple.MobileSMS"];

    NSArray *timeApps = (hour < 12) ? morningApps : eveningApps;

    for (NSString *bundleId in timeApps) {
        @try {
            id appController = [NSClassFromString(@"SBApplicationController") sharedInstance];
            id app = [appController applicationWithDisplayIdentifier:bundleId];
            if (app) [suggested addObject:app];
        } @catch (NSException *e) {}
    }

    [_suggestedApps release];
    _suggestedApps = [suggested retain];

    /* Build suggested app buttons */
    for (UIView *v in [_suggestedScroll subviews]) [v removeFromSuperview];

    CGFloat x = 12;
    for (id app in _suggestedApps) {
        NSString *name = [app displayName];
        NSString *bundleId = [app displayIdentifier];

        UIView *card = [[[UIView alloc] initWithFrame:CGRectMake(x, 0, 60, 72)] autorelease];
        card.backgroundColor = [UIColor clearColor];

        /* Icon placeholder (colored circle with first letter) */
        UIView *iconBg = [[[UIView alloc] initWithFrame:CGRectMake(6, 0, 48, 48)] autorelease];
        iconBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12f];
        iconBg.layer.cornerRadius = 12;

        UILabel *iconLetter = [[[UILabel alloc] initWithFrame:iconBg.bounds] autorelease];
        iconLetter.text = [name substringToIndex:MIN(2, [name length])];
        iconLetter.textColor = [UIColor whiteColor];
        iconLetter.font = [UIFont boldSystemFontOfSize:18];
        iconLetter.textAlignment = NSTextAlignmentCenter;
        iconLetter.backgroundColor = [UIColor clearColor];
        [iconBg addSubview:iconLetter];
        [card addSubview:iconBg];

        UILabel *nameLabel = [[[UILabel alloc] initWithFrame:CGRectMake(0, 52, 60, 14)] autorelease];
        nameLabel.text = name;
        nameLabel.textColor = [UIColor colorWithWhite:0.7f alpha:1];
        nameLabel.font = [UIFont systemFontOfSize:10];
        nameLabel.textAlignment = NSTextAlignmentCenter;
        nameLabel.backgroundColor = [UIColor clearColor];
        [card addSubview:nameLabel];

        /* Tap to launch */
        UIButton *tapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        tapBtn.frame = card.bounds;
        tapBtn.accessibilityLabel = bundleId; /* Store bundle ID */
        [tapBtn addTarget:self action:@selector(_appTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:tapBtn];

        [_suggestedScroll addSubview:card];
        x += 68;
    }
    _suggestedScroll.contentSize = CGSizeMake(x, 76);
}

- (void)_buildFeed {
    [_feedItems removeAllObjects];

    /* Add some contextual feed items */
    [_feedItems addObject:@{@"type": @"tip",
        @"text": @"Type a command or app name above to get started. Try: 'open safari' or 'set a timer for 5 minutes'"}];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    if (![[prefs objectForKey:@"apiKey"] length]) {
        [_feedItems addObject:@{@"type": @"setup",
            @"text": @"Set up your API key in Settings > ClawPod to enable AI features."}];
    }

    [_feedItems addObject:@{@"type": @"info",
        @"text": [NSString stringWithFormat:@"%lu apps installed", (unsigned long)[_allApps count]]}];

    [_feedTable reloadData];
}

#pragma mark - Actions

- (void)_appTapped:(UIButton *)btn {
    NSString *bundleId = btn.accessibilityLabel;
    if (bundleId) [self launchApp:bundleId];
}

- (void)_actionTapped:(UIButton *)btn {
    NSString *title = [btn titleForState:UIControlStateNormal];
    if ([title isEqualToString:@"Ask AI"]) {
        notify_post("ai.openclaw.ios6/shakeActivate");
    } else if ([title isEqualToString:@"Settings"]) {
        [self launchApp:@"com.apple.Preferences"];
    } else if ([title isEqualToString:@"Messages"]) {
        [self launchApp:@"com.apple.MobileSMS"];
    } else if ([title isEqualToString:@"Safari"]) {
        [self launchApp:@"com.apple.mobilesafari"];
    } else if ([title isEqualToString:@"Music"]) {
        [self launchApp:@"com.apple.Music"];
    } else if ([title isEqualToString:@"Photos"]) {
        [self launchApp:@"com.apple.mobileslideshow"];
    }
}

- (void)_dismissKB { [_commandField resignFirstResponder]; }

- (void)launchApp:(NSString *)bundleId {
    @try {
        id appController = [NSClassFromString(@"SBApplicationController") sharedInstance];
        id app = [appController applicationWithDisplayIdentifier:bundleId];
        if (app) {
            id uiController = [NSClassFromString(@"SBUIController") sharedInstance];
            [uiController activateApplicationAnimated:app];
        }
    } @catch (NSException *e) {
        NSLog(@"[CPLauncher] Failed to launch %@: %@", bundleId, e);
    }
}

- (void)showResultsForQuery:(NSString *)query {
    if (!query || [query length] == 0) {
        _isSearching = NO;
        [_feedTable reloadData];
        return;
    }

    /* Search installed apps by name */
    NSString *lower = [query lowercaseString];
    NSMutableArray *results = [NSMutableArray array];

    for (id app in _allApps) {
        NSString *name = [[app displayName] lowercaseString];
        NSString *bundleId = [[app displayIdentifier] lowercaseString];
        if ([name rangeOfString:lower].location != NSNotFound ||
            [bundleId rangeOfString:lower].location != NSNotFound) {
            [results addObject:app];
        }
    }

    [_searchResults release];
    _searchResults = [results retain];
    _isSearching = YES;
    [_feedTable reloadData];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    NSString *text = [tf.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0) return NO;

    /* Check for "open <app>" pattern */
    if ([[text lowercaseString] hasPrefix:@"open "]) {
        NSString *appName = [[text substringFromIndex:5]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self showResultsForQuery:appName];
    } else {
        /* Send to AI via notification */
        NSDictionary *data = @{@"query": text};
        [data writeToFile:@"/tmp/clawpod-query.plist" atomically:YES];
        notify_post("ai.openclaw.ios6/shakeActivate");
    }

    tf.text = @"";
    [tf resignFirstResponder];
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)tf {
    _isSearching = NO;
}

- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range
 replacementString:(NSString *)string {
    NSString *newText = [tf.text stringByReplacingCharactersInRange:range withString:string];
    if ([newText length] > 0) {
        [self showResultsForQuery:newText];
    } else {
        _isSearching = NO;
        [_feedTable reloadData];
    }
    return YES;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _isSearching ? [_searchResults count] : [_feedItems count];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (_isSearching) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"App"];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:@"App"] autorelease];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
        }
        id app = [_searchResults objectAtIndex:ip.row];
        cell.textLabel.text = [app displayName];
        cell.detailTextLabel.text = [app displayIdentifier];
        return cell;
    }

    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Feed"];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"Feed"] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.7f alpha:1];
        cell.textLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *item = [_feedItems objectAtIndex:ip.row];
    cell.textLabel.text = [item objectForKey:@"text"];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (_isSearching && ip.row < (NSInteger)[_searchResults count]) {
        id app = [_searchResults objectAtIndex:ip.row];
        [self launchApp:[app displayIdentifier]];
    }
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return _isSearching ? 50 : 60;
}

@end
