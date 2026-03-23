/*
 * ClawPod SpringBoard Tweak
 * iOS 6 System Integration — Siri-like AI overlay
 *
 * Hooks _menuButtonWasHeld on SpringBoard to intercept home button hold,
 * replacing Voice Control with the ClawPod AI assistant overlay.
 *
 * Based on iOS 6 private headers from class-dump.
 * Method signatures verified against iOS-6-Headers/SpringBoard/SpringBoard.h
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <notify.h>

/* SpringBoard class (from iOS-6-Headers/SpringBoard/SpringBoard.h) */
@interface SpringBoard : UIApplication
- (void)menuButtonDown:(struct __GSEvent *)event;
- (void)menuButtonUp:(struct __GSEvent *)event;
- (void)_menuButtonWasHeld;
- (double)_menuHoldTime;
- (void)clearMenuButtonTimer;
@end

/* SBUIController (from iOS-6-Headers/SpringBoard/SBUIController.h) */
@interface SBUIController : NSObject
+ (id)sharedInstance;
- (BOOL)clickedMenuButton;
@end

/* SBVoiceControlController (from iOS-6-Headers/SpringBoard/SBVoiceControlController.h) */
@interface SBVoiceControlController : NSObject
+ (id)sharedInstance;
- (BOOL)handleHomeButtonHeld;
@end

#define PREFS_PATH @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"
#define PANEL_HEIGHT 290.0f
#define ANIM_DURATION 0.28f

#pragma mark - ClawPod Overlay Panel

@interface CPAssistantPanel : UIView <UITextFieldDelegate, NSURLConnectionDataDelegate> {
    UIView *_dimView;
    UIView *_panel;
    UITextField *_inputField;
    UITextView *_responseArea;
    UIView *_typingDots;
    UIButton *_closeBtn;

    BOOL _isProcessing;
    NSMutableString *_streamBuf;
    NSMutableString *_sseBuf;
    NSURLConnection *_conn;
}
@property (nonatomic, assign) BOOL isVisible;
- (void)show;
- (void)dismiss;
@end

@implementation CPAssistantPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = YES;
        _streamBuf = [[NSMutableString alloc] init];
        _sseBuf = [[NSMutableString alloc] init];
        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;

        /* Dim background - NO tap to dismiss (only swipe/close/home) */
        _dimView = [[UIView alloc] initWithFrame:frame];
        _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35f];
        _dimView.alpha = 0;
        _dimView.userInteractionEnabled = NO; /* Pass touches through */
        [self addSubview:_dimView];

        /* Panel - slides up from bottom, rounded top corners */
        _panel = [[UIView alloc] initWithFrame:CGRectMake(0, h, w, PANEL_HEIGHT)];
        _panel.backgroundColor = [UIColor colorWithRed:0.06f green:0.06f blue:0.10f alpha:0.96f];
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, PANEL_HEIGHT)
            byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
            cornerRadii:CGSizeMake(14, 14)] CGPath];
        _panel.layer.mask = mask;
        [self addSubview:_panel];

        /* Grab handle */
        UIView *handle = [[[UIView alloc] initWithFrame:CGRectMake((w-36)/2, 6, 36, 4)] autorelease];
        handle.backgroundColor = [UIColor colorWithWhite:0.45f alpha:0.7f];
        handle.layer.cornerRadius = 2;
        [_panel addSubview:handle];

        /* Title bar with close button */
        UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(0, 14, w, 22)] autorelease];
        title.text = @"ClawPod";
        title.textColor = [UIColor colorWithRed:0.92f green:0.30f blue:0.30f alpha:1.0f];
        title.font = [UIFont boldSystemFontOfSize:16];
        title.textAlignment = NSTextAlignmentCenter;
        title.backgroundColor = [UIColor clearColor];
        [_panel addSubview:title];

        _closeBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _closeBtn.frame = CGRectMake(w - 44, 10, 34, 28);
        [_closeBtn setTitle:@"\u2715" forState:UIControlStateNormal];
        [_closeBtn setTitleColor:[UIColor colorWithWhite:0.5f alpha:1] forState:UIControlStateNormal];
        _closeBtn.titleLabel.font = [UIFont systemFontOfSize:18];
        [_closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:_closeBtn];

        /* Response text area */
        _responseArea = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, w - 20, PANEL_HEIGHT - 40 - 50)];
        _responseArea.backgroundColor = [UIColor clearColor];
        _responseArea.textColor = [UIColor colorWithWhite:0.85f alpha:1];
        _responseArea.font = [UIFont systemFontOfSize:14.5f];
        _responseArea.editable = NO;
        _responseArea.text = @"Hold home button to ask me anything.";
        [_panel addSubview:_responseArea];

        /* Typing dots */
        _typingDots = [[UIView alloc] initWithFrame:CGRectMake(14, 44, 44, 16)];
        _typingDots.hidden = YES;
        for (int i = 0; i < 3; i++) {
            UIView *d = [[[UIView alloc] initWithFrame:CGRectMake(i * 13, 4, 7, 7)] autorelease];
            d.backgroundColor = [UIColor colorWithWhite:0.55f alpha:1];
            d.layer.cornerRadius = 3.5f;
            d.tag = 600 + i;
            [_typingDots addSubview:d];
        }
        [_panel addSubview:_typingDots];

        /* Input bar */
        UIView *bar = [[[UIView alloc] initWithFrame:CGRectMake(0, PANEL_HEIGHT - 44, w, 44)] autorelease];
        bar.backgroundColor = [UIColor colorWithRed:0.10f green:0.10f blue:0.14f alpha:1];
        UIView *bdr = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5f)] autorelease];
        bdr.backgroundColor = [UIColor colorWithWhite:0.22f alpha:1];
        [bar addSubview:bdr];
        [_panel addSubview:bar];

        _inputField = [[UITextField alloc] initWithFrame:CGRectMake(10, 6, w - 70, 32)];
        _inputField.backgroundColor = [UIColor colorWithRed:0.16f green:0.16f blue:0.22f alpha:1];
        _inputField.textColor = [UIColor whiteColor];
        _inputField.font = [UIFont systemFontOfSize:14.5f];
        _inputField.layer.cornerRadius = 16;
        _inputField.layer.masksToBounds = YES;
        _inputField.placeholder = @"Ask anything...";
        _inputField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _inputField.delegate = self;
        _inputField.returnKeyType = UIReturnKeySend;
        _inputField.autocorrectionType = UITextAutocorrectionTypeDefault;
        UIView *lpad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 32)] autorelease];
        _inputField.leftView = lpad;
        _inputField.leftViewMode = UITextFieldViewModeAlways;
        [bar addSubview:_inputField];

        UIButton *send = [UIButton buttonWithType:UIButtonTypeCustom];
        send.frame = CGRectMake(w - 56, 6, 48, 32);
        [send setTitle:@"Send" forState:UIControlStateNormal];
        [send setTitleColor:[UIColor colorWithRed:0.92f green:0.30f blue:0.30f alpha:1] forState:UIControlStateNormal];
        send.titleLabel.font = [UIFont boldSystemFontOfSize:14.5f];
        [send addTarget:self action:@selector(_send) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:send];

        /* Tap on response area dismisses keyboard (not panel) */
        UITapGestureRecognizer *kbDismiss = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(_dismissKeyboard)];
        kbDismiss.cancelsTouchesInView = NO;
        [_responseArea addGestureRecognizer:kbDismiss];
        [kbDismiss release];

        /* Swipe down to dismiss panel */
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc]
            initWithTarget:self action:@selector(dismiss)];
        swipe.direction = UISwipeGestureRecognizerDirectionDown;
        [_panel addGestureRecognizer:swipe];
        [swipe release];

        /* Listen for keyboard */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_kbShow:)
            name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_kbHide:)
            name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_dimView release]; [_panel release]; [_inputField release];
    [_responseArea release]; [_typingDots release]; [_closeBtn release];
    [_streamBuf release]; [_sseBuf release]; [_conn release];
    [super dealloc];
}

#pragma mark Show/Dismiss

- (void)show {
    if (_isVisible) return;
    _isVisible = YES;
    CGFloat h = self.bounds.size.height;
    _dimView.alpha = 0;
    _panel.frame = CGRectMake(0, h, self.bounds.size.width, PANEL_HEIGHT);

    [UIView animateWithDuration:ANIM_DURATION delay:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
        _dimView.alpha = 1;
        _panel.frame = CGRectMake(0, h - PANEL_HEIGHT, self.bounds.size.width, PANEL_HEIGHT);
    } completion:nil];
}

- (void)dismiss {
    if (!_isVisible) return;
    _isVisible = NO;

    /* Force keyboard away FIRST, before anything else */
    [_inputField resignFirstResponder];
    /* Nuclear option: tell the entire app to end editing */
    [self.window endEditing:YES];

    [_conn cancel];
    CGFloat h = self.bounds.size.height;

    /* Small delay to let keyboard dismiss begin, then animate panel */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:ANIM_DURATION delay:0
            options:UIViewAnimationOptionCurveEaseIn animations:^{
            _dimView.alpha = 0;
            _panel.frame = CGRectMake(0, h, self.bounds.size.width, PANEL_HEIGHT);
        } completion:^(BOOL f) {
            UIWindow *myWindow = self.window;
            if (myWindow) {
                myWindow.hidden = YES;
                /* Ensure keyboard is gone by ending editing again after hide */
                [myWindow endEditing:YES];
                [[[UIApplication sharedApplication] keyWindow] makeKeyWindow];
            }
        }];
    });
}

#pragma mark Keyboard

- (void)_kbShow:(NSNotification *)n {
    CGFloat kbH = [[[n userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    NSTimeInterval dur = [[[n userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGFloat h = self.bounds.size.height;
    [UIView animateWithDuration:dur animations:^{
        _panel.frame = CGRectMake(0, h - kbH - PANEL_HEIGHT, self.bounds.size.width, PANEL_HEIGHT);
    }];
}

- (void)_kbHide:(NSNotification *)n {
    NSTimeInterval dur = [[[n userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGFloat h = self.bounds.size.height;
    [UIView animateWithDuration:dur animations:^{
        _panel.frame = CGRectMake(0, h - PANEL_HEIGHT, self.bounds.size.width, PANEL_HEIGHT);
    }];
}

- (void)_dismissKeyboard {
    [_inputField resignFirstResponder];
}

#pragma mark Input

- (void)_send {
    NSString *q = [_inputField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([q length] == 0 || _isProcessing) return;
    _inputField.text = @"";

    /* Show user query */
    _responseArea.textColor = [UIColor colorWithRed:0.5f green:0.7f blue:1.0f alpha:1];
    _responseArea.text = q;

    /* Show typing */
    _typingDots.hidden = NO;
    for (int i = 0; i < 3; i++) {
        UIView *d = [_typingDots viewWithTag:600 + i];
        d.alpha = 1;
        [UIView animateWithDuration:0.35 delay:i * 0.12
            options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
            animations:^{ d.alpha = 0.25f; } completion:nil];
    }

    _isProcessing = YES;
    [_streamBuf setString:@""];
    [_sseBuf setString:@""];

    /* Get API key from prefs */
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *apiKey = [prefs objectForKey:@"apiKey"];
    NSString *model = [prefs objectForKey:@"modelId"] ?: @"claude-sonnet-4-20250514";

    if (!apiKey || [apiKey length] == 0) {
        [self _showResult:@"No API key set.\n\nGo to Settings \u2192 ClawPod."]; return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [req setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];

    NSDictionary *body = @{
        @"model": model,
        @"max_tokens": @(1024),
        @"stream": @YES,
        @"system": @"You are Molty, a concise AI assistant on an iPod Touch via ClawPod. "
                    "Keep answers brief. You appear as a system overlay like Siri.",
        @"messages": @[@{@"role": @"user", @"content": q}]
    };
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];

    [_conn release];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self _send]; return NO; }

#pragma mark Streaming

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!chunk) { [chunk release]; return; }
    [_sseBuf appendString:chunk];
    [chunk release];

    NSArray *lines = [_sseBuf componentsSeparatedByString:@"\n"];
    [_sseBuf setString:[lines lastObject] ?: @""];

    for (NSUInteger i = 0; i < [lines count] - 1; i++) {
        NSString *line = [lines objectAtIndex:i];
        if (![line hasPrefix:@"data: "]) continue;
        NSString *json = [line substringFromIndex:6];
        if ([json isEqualToString:@"[DONE]"]) continue;
        NSDictionary *evt = [NSJSONSerialization JSONObjectWithData:
            [json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (!evt) continue;
        if ([[evt objectForKey:@"type"] isEqualToString:@"content_block_delta"]) {
            NSString *text = [[evt objectForKey:@"delta"] objectForKey:@"text"];
            if (text) {
                [_streamBuf appendString:text];
                dispatch_async(dispatch_get_main_queue(), ^{
                    _typingDots.hidden = YES;
                    _responseArea.textColor = [UIColor colorWithWhite:0.88f alpha:1];
                    _responseArea.text = _streamBuf;
                });
            }
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    dispatch_async(dispatch_get_main_queue(), ^{
        _isProcessing = NO;
        _typingDots.hidden = YES;
    });
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _showResult:[NSString stringWithFormat:@"Error: %@", [error localizedDescription]]];
    });
}

- (void)_showResult:(NSString *)text {
    _isProcessing = NO;
    _typingDots.hidden = YES;
    _responseArea.textColor = [UIColor colorWithWhite:0.88f alpha:1];
    _responseArea.text = text;
}

@end

#pragma mark - App Switcher Widget

/*
 * Status widget that appears as a page to the LEFT of the music controls
 * in the iOS 6 app switcher (double-tap home bar).
 *
 * SBNowPlayingBar's `views` method returns an array of UIViews used as
 * pages in the auxiliary scroll area. We prepend our widget.
 */

/* Forward declaration */
@interface SBNowPlayingBar : NSObject
- (id)views;
- (void)viewAtIndexDidAppear:(int)idx;
- (void)viewAtIndexDidDisappear:(int)idx;
@end

@interface SBAppSwitcherController : NSObject
+ (id)sharedInstance;
@end

@interface CPWidgetView : UIView {
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_sessionsLabel;
    UILabel *_memoryLabel;
    UILabel *_gatewayLabel;
    UIButton *_openButton;
}
- (void)refreshStatus;
@end

@implementation CPWidgetView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        CGFloat w = frame.size.width;

        /* Title */
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, w, 18)];
        _titleLabel.text = @"ClawPod";
        _titleLabel.textColor = [UIColor colorWithRed:0.92f green:0.30f blue:0.30f alpha:1.0f];
        _titleLabel.font = [UIFont boldSystemFontOfSize:13];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];

        /* Status line */
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 26, w - 20, 14)];
        _statusLabel.font = [UIFont systemFontOfSize:11];
        _statusLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_statusLabel];

        /* Gateway status */
        _gatewayLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 42, w - 20, 12)];
        _gatewayLabel.font = [UIFont systemFontOfSize:10];
        _gatewayLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1];
        _gatewayLabel.textAlignment = NSTextAlignmentCenter;
        _gatewayLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_gatewayLabel];

        /* Memory */
        _memoryLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 56, w - 20, 12)];
        _memoryLabel.font = [UIFont systemFontOfSize:10];
        _memoryLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1];
        _memoryLabel.textAlignment = NSTextAlignmentCenter;
        _memoryLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_memoryLabel];

        /* Open button */
        _openButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _openButton.frame = CGRectMake((w - 80) / 2, 72, 80, 24);
        _openButton.backgroundColor = [UIColor colorWithRed:0.92f green:0.30f blue:0.30f alpha:0.8f];
        _openButton.layer.cornerRadius = 12;
        _openButton.layer.masksToBounds = YES;
        [_openButton setTitle:@"Open" forState:UIControlStateNormal];
        [_openButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _openButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [_openButton addTarget:self action:@selector(_openApp) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_openButton];

        [self refreshStatus];
    }
    return self;
}

- (void)dealloc {
    [_titleLabel release]; [_statusLabel release]; [_sessionsLabel release];
    [_memoryLabel release]; [_gatewayLabel release]; [_openButton release];
    [super dealloc];
}

- (void)refreshStatus {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *host = [prefs objectForKey:@"gatewayHost"];
    BOOL hasKey = [[prefs objectForKey:@"apiKey"] length] > 0;

    if (host && [host length] > 0) {
        _statusLabel.text = [NSString stringWithFormat:@"Gateway: %@", host];
        _statusLabel.textColor = [UIColor colorWithRed:0.3f green:0.85f blue:0.5f alpha:1];
    } else if (hasKey) {
        _statusLabel.text = @"Direct API Mode";
        _statusLabel.textColor = [UIColor colorWithRed:0.4f green:0.7f blue:1.0f alpha:1];
    } else {
        _statusLabel.text = @"Not Configured";
        _statusLabel.textColor = [UIColor colorWithRed:1.0f green:0.5f blue:0.3f alpha:1];
    }

    _gatewayLabel.text = hasKey ? @"API Key: Set" : @"API Key: Not Set";

    /* Memory info via mach */
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                  (task_info_t)&info, &count);
    if (kr == KERN_SUCCESS) {
        _memoryLabel.text = [NSString stringWithFormat:@"SpringBoard: %.1f MB",
            info.resident_size / (1024.0 * 1024.0)];
    }
}

- (void)_openApp {
    /* Launch ClawPod app */
    NSURL *url = [NSURL URLWithString:@"openclaw://"];
    [[UIApplication sharedApplication] openURL:url];
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow) [self refreshStatus];
}

@end

static CPWidgetView *_cpWidgetView = nil;

/*
 * Hook SBNowPlayingBar to inject our widget as a page.
 * The `views` method returns an NSArray of UIViews that become
 * the auxiliary pages (left of app icons) in the switcher.
 * We prepend our widget so it appears to the left of music controls.
 *
 * Compatible with other tweaks: we only prepend, never replace.
 * Other tweaks that also hook `views` will still see theirs.
 */
%hook SBNowPlayingBar

- (id)views {
    NSArray *origViews = %orig;

    /* Create widget if needed, matching the size of existing views */
    if (!_cpWidgetView) {
        CGRect frame;
        if ([origViews count] > 0) {
            frame = [[origViews objectAtIndex:0] frame];
        } else {
            /* Fallback size: full width of switcher bar, standard height */
            frame = CGRectMake(0, 0, 320, 96);
        }
        _cpWidgetView = [[CPWidgetView alloc] initWithFrame:frame];
    }

    [_cpWidgetView refreshStatus];

    /* Prepend our widget to the left of existing pages */
    NSMutableArray *allViews = [NSMutableArray arrayWithObject:_cpWidgetView];
    [allViews addObjectsFromArray:origViews];
    return allViews;
}

/* Adjust index for appearance/disappearance callbacks so existing
   pages still get correct indices (offset by 1 for our added page) */
- (void)viewAtIndexDidAppear:(int)idx {
    if (idx == 0) {
        [_cpWidgetView refreshStatus];
        return; /* Our widget — don't pass to orig */
    }
    %orig(idx - 1); /* Offset for original pages */
}

- (void)viewAtIndexDidDisappear:(int)idx {
    if (idx == 0) return; /* Our widget */
    %orig(idx - 1);
}

%end

#pragma mark - Global State

static UIWindow *_cpWindow = nil;
static CPAssistantPanel *_cpPanel = nil;
static BOOL _cpGracePeriod = NO; /* Ignore home-up right after hold-to-show */

static void CPShow(void) {
    if (!_cpWindow) {
        CGRect bounds = [[UIScreen mainScreen] bounds];
        _cpWindow = [[UIWindow alloc] initWithFrame:bounds];
        _cpWindow.windowLevel = 9999;
        _cpWindow.backgroundColor = [UIColor clearColor];
        _cpWindow.userInteractionEnabled = YES;
        _cpPanel = [[CPAssistantPanel alloc] initWithFrame:bounds];
        [_cpWindow addSubview:_cpPanel];
    }

    if (_cpPanel.isVisible) return; /* Already showing */

    _cpWindow.hidden = NO;
    [_cpWindow makeKeyAndVisible]; /* Must be key window for text input to work */
    [_cpPanel show];

    /* Grace period: ignore home button events for 0.8s after showing,
       so the button-up from the hold doesn't immediately dismiss */
    _cpGracePeriod = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ _cpGracePeriod = NO; });
}

static void CPDismiss(void) {
    if (!_cpPanel || !_cpPanel.isVisible) return;
    [_cpPanel dismiss];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            _cpWindow.hidden = YES;
            /* Restore SpringBoard as key window */
            [[[UIApplication sharedApplication] keyWindow] makeKeyWindow];
        });
}

#pragma mark - SpringBoard Hook: Intercept Home Button Hold

/*
 * On iOS 6, holding the home button triggers _menuButtonWasHeld on SpringBoard,
 * which calls SBVoiceControlController handleHomeButtonHeld → Voice Control.
 * We replace that with our AI overlay. Only SHOW here, never dismiss.
 */
%hook SpringBoard

- (void)_menuButtonWasHeld {
    CPShow();
    /* Do NOT call %orig — prevents Voice Control from launching */
}

/*
 * _handleMenuButtonEvent fires on EVERY home button press, before
 * the keyboard or any other responder gets a chance to consume it.
 * This is the reliable place to catch home presses while our
 * overlay is showing (even when keyboard is up).
 */
- (void)_handleMenuButtonEvent {
    if (_cpPanel && _cpPanel.isVisible && !_cpGracePeriod) {
        CPDismiss();
        return; /* Consume the event — don't pass to SpringBoard */
    }
    %orig;
}

%end

/* Fallback: also hook clickedMenuButton in case _handleMenuButtonEvent
   doesn't fire in some code paths */
%hook SBUIController

- (BOOL)clickedMenuButton {
    if (_cpPanel && _cpPanel.isVisible) {
        if (_cpGracePeriod) {
            return YES; /* Ignore button-up from hold */
        }
        CPDismiss();
        return YES;
    }
    return %orig;
}

%end

#pragma mark - Notification Center Widget Registration

@interface SBBulletinListController : NSObject
+ (id)sharedInstance;
- (id)_weeAppForSectionID:(id)sectionID;
@end

@interface SBWeeApp : NSObject
- (id)initWithWeeAppController:(id)controller sectionID:(id)sectionID;
- (void)setDelegate:(id)delegate;
@end

static NSString *const kCPWidgetSectionID = @"ai.openclaw.nc-widget";

%hook SBBulletinListController

- (void)_loadSections {
    %orig;

    if ([self _weeAppForSectionID:kCPWidgetSectionID]) return;

    NSBundle *wb = [NSBundle bundleWithPath:@"/System/Library/WeeAppPlugins/OpenClawNC.bundle"];
    if (!wb || ![wb load]) { NSLog(@"[ClawPod] NC bundle load failed"); return; }

    Class cls = [wb principalClass];
    if (!cls) { NSLog(@"[ClawPod] NC no principal class"); return; }

    id controller = [[cls alloc] init];
    SBWeeApp *wa = [[%c(SBWeeApp) alloc] initWithWeeAppController:controller
                                                         sectionID:kCPWidgetSectionID];
    [wa setDelegate:self];
    [controller release];

    NSMutableArray *weeApps = [self valueForKey:@"_weeApps"];
    NSMutableArray *visible = [self valueForKey:@"_visibleWeeApps"];
    if (weeApps) [weeApps addObject:wa];
    if (visible) [visible insertObject:wa atIndex:0];
    [wa release];

    /* Reload table to show the new widget */
    [self performSelector:@selector(_reloadTableView) withObject:nil afterDelay:0.5];

    NSLog(@"[ClawPod] NC widget injected");
}

/* Provide display name for our section in Settings > Notifications */
- (id)tableView:(id)tv cellForRowAtIndexPath:(id)ip {
    id cell = %orig;
    /* Check if this is our section and set the label */
    @try {
        if ([cell respondsToSelector:@selector(textLabel)]) {
            UILabel *label = [cell performSelector:@selector(textLabel)];
            if (label && [[label text] length] == 0) {
                /* Might be our unlabeled widget - check the section */
            }
        }
    } @catch (NSException *e) {}
    return cell;
}

%end

/*
 * Fix NC widget display name in Settings > Notifications.
 * Hook BBSectionInfo to provide our display name when the section ID matches.
 */
%hook BBSectionInfo

- (id)displayName {
    NSString *sid = nil;
    @try { sid = [self valueForKey:@"sectionID"]; } @catch (NSException *e) {}
    if (sid && [sid isEqualToString:kCPWidgetSectionID]) {
        return @"ClawPod";
    }
    return %orig;
}

%end

#pragma mark - Lock Screen Widget

/*
 * Add ClawPod status below the date on the lock screen.
 * SBAwayView has ivar _dateHeaderView (SBAwayDateView).
 * Hook viewDidLayoutSubviews safely - avoid layoutSubviews
 * which fires too frequently and can cause recursion.
 */

@interface SBAwayView : UIView
@end

static UILabel *_lsLabel = nil;

%hook SBAwayView

- (void)didMoveToWindow {
    %orig;

    if (!_lsLabel && self.window) {
        CGFloat w = self.bounds.size.width;
        _lsLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 96, w - 20, 18)];
        _lsLabel.font = [UIFont systemFontOfSize:11];
        _lsLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55f];
        _lsLabel.textAlignment = NSTextAlignmentCenter;
        _lsLabel.backgroundColor = [UIColor clearColor];
        _lsLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.5f];
        _lsLabel.shadowOffset = CGSizeMake(0, 1);
        _lsLabel.tag = 31337;
        [self addSubview:_lsLabel];
    }

    /* Position below date header if available */
    @try {
        UIView *dateHeader = [self valueForKey:@"_dateHeaderView"];
        if (dateHeader && _lsLabel) {
            CGRect df = dateHeader.frame;
            _lsLabel.frame = CGRectMake(10, CGRectGetMaxY(df) + 2,
                                         self.bounds.size.width - 20, 18);
        }
    } @catch (NSException *e) {}

    /* Update text */
    if (_lsLabel) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
        NSString *host = [prefs objectForKey:@"gatewayHost"];
        BOOL hasKey = [[prefs objectForKey:@"apiKey"] length] > 0;

        if (host && [host length] > 0)
            _lsLabel.text = [NSString stringWithFormat:@"ClawPod - %@", host];
        else if (hasKey)
            _lsLabel.text = @"ClawPod - Ready";
        else
            _lsLabel.text = @"ClawPod";
    }
}

%end

#pragma mark - Lock Screen Camera Slider → ClawPod

/*
 * Replace the lock screen camera shortcut with ClawPod activation.
 * Hook SBAwayController's camera gesture to show our overlay instead.
 */

@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)handleMenuButtonHeld;
- (void)unlockWithSound:(BOOL)sound unlockSource:(int)source;
@end

%hook SBAwayController

- (void)handleCameraPanGesture:(id)gesture {
    /* Instead of camera, unlock and show ClawPod */
    @try {
        if ([self respondsToSelector:@selector(unlockWithSound:unlockSource:)]) {
            [self unlockWithSound:YES unlockSource:0];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ CPShow(); });
        } else {
            %orig; /* Fall back to camera if unlock method unavailable */
        }
    } @catch (NSException *e) {
        %orig;
    }
}

%end

#pragma mark - Spotlight Search Integration

%hook SBSearchController

- (void)searchBarSearchButtonClicked:(id)bar {
    %orig;
    NSString *query = nil;
    @try {
        if ([bar respondsToSelector:@selector(text)])
            query = [bar performSelector:@selector(text)];
    } @catch (NSException *e) {}
    if (query && [query length] > 2) {
        CPShow();
    }
}

%end

#pragma mark - Bluetooth Headset → ClawPod

/*
 * Route Bluetooth headset voice control button to ClawPod
 * instead of the stock Voice Control.
 */

%hook SBVoiceControlController

- (BOOL)handleHomeButtonHeld {
    /* Already intercepted by _menuButtonWasHeld, but just in case */
    CPShow();
    return YES;
}

- (void)_performDelayedHeadsetActionForVoiceControl {
    /* BT headset long-press → ClawPod instead of Voice Control */
    CPShow();
}

- (void)_performDelayedHeadsetActionForAssistant {
    /* BT headset → ClawPod instead of Siri */
    CPShow();
}

%end

#pragma mark - Media Controller Integration

/*
 * When ClawPod TTS is speaking, show it in the Now Playing controls.
 */

@interface SBMediaController : NSObject
+ (id)sharedInstance;
- (id)nowPlayingApplication;
- (NSString *)nowPlayingTitle;
@end

%hook SBMediaController

- (id)nowPlayingTitle {
    /* If ClawPod is speaking, show that */
    NSString *orig = %orig;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/clawpod-speaking"]) {
        return @"ClawPod is speaking...";
    }
    return orig;
}

%end

#pragma mark - Dynamic Badge on App Icon

/*
 * Show unread channel message count as badge on ClawPod app icon.
 */

@interface SBIconModel : NSObject
- (id)applicationIconForDisplayIdentifier:(id)displayId;
@end

@interface SBIcon : NSObject
- (void)setBadge:(id)badge;
- (void)noteBadgeDidChange;
@end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app {
    %orig;

    /* Listen for badge updates from ClawPod app */
    int badgeToken;
    notify_register_dispatch("ai.openclaw.ios6/updateBadge", &badgeToken,
        dispatch_get_main_queue(), ^(int t) {
            NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:
                @"/tmp/clawpod-badge.plist"];
            NSNumber *count = [data objectForKey:@"count"];
            if (!count) return;

            SBIconModel *model = [[%c(SBIconController) sharedInstance] performSelector:@selector(model)];
            SBIcon *icon = [model applicationIconForDisplayIdentifier:@"ai.openclaw.ios6"];
            if (icon) {
                [icon setBadge:[count intValue] > 0 ? [count stringValue] : nil];
                [icon noteBadgeDidChange];
            }
        });

    /* Listen for banner requests */
    int bannerToken;
    notify_register_dispatch("ai.openclaw.ios6/showBanner", &bannerToken,
        dispatch_get_main_queue(), ^(int t) {
            NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:
                @"/tmp/openclaw-banner.plist"];
            if (!data) return;

            Class BBBulletin = %c(BBBulletin);
            if (!BBBulletin) return;

            id bulletin = [[BBBulletin alloc] init];
            [bulletin setValue:@"ai.openclaw.ios6" forKey:@"sectionID"];
            [bulletin setValue:[data objectForKey:@"title"] ?: @"ClawPod" forKey:@"title"];
            [bulletin setValue:[data objectForKey:@"message"] ?: @"" forKey:@"message"];
            [bulletin setValue:[NSDate date] forKey:@"date"];
            [bulletin setValue:[NSString stringWithFormat:@"clawpod-%f",
                [[NSDate date] timeIntervalSince1970]] forKey:@"bulletinID"];

            id bc = [%c(SBBulletinBannerController) sharedInstance];
            if (bc) {
                @try {
                    [bc performSelector:@selector(observer:addBulletin:forFeed:)
                             withObject:nil withObject:bulletin];
                } @catch (NSException *e) {}
            }
            [bulletin release];
        });

    NSLog(@"[ClawPod] System hooks initialized");
}

%end

#pragma mark - Auto-Launch Gateway on Boot

/*
 * Notify the ClawPod app to start the gateway server when
 * SpringBoard finishes launching (device boot).
 */

%hook SBUIController

- (void)finishedBooting {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            notify_post("ai.openclaw.ios6/autoStart");
            NSLog(@"[ClawPod] Boot complete, sent autoStart notification");
        });
}

%end

#pragma mark - Spotlight Dashboard (SBSettings-style)

/*
 * Replace the Spotlight search page (swipe left from home screen)
 * with a ClawPod dashboard showing toggles, status, quick actions.
 * Like SBSettings but integrated into the Spotlight page.
 */

/*
 * Hook SBIconController to detect when Spotlight page is visible.
 * _showSearchKeyboardIfNecessary: fires when scroll settles on search page.
 * isShowingSearch returns YES when on the search page.
 * We overlay our dashboard onto _searchView.
 */

@interface SBIconController : NSObject
+ (id)sharedInstance;
- (BOOL)isShowingSearch;
- (id)searchView; /* returns SBSearchView */
@end

@interface SBSearchView : UIView
@property (readonly, nonatomic) UISearchBar *searchBar;
@property (readonly, nonatomic) UITableView *tableView;
@end

static UIView *_dashboardView = nil;

static UIView *_buildDashboard(CGRect frame) {
    UIView *dash = [[[UIView alloc] initWithFrame:frame] autorelease];
    dash.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
    CGFloat w = frame.size.width;
    CGFloat y = 50; /* Below search bar */

    /* Title */
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(0, y, w, 28)] autorelease];
    title.text = @"ClawPod Dashboard";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    title.backgroundColor = [UIColor clearColor];
    [dash addSubview:title];
    y += 34;

    /* Status section */
    UILabel *statusHeader = [[[UILabel alloc] initWithFrame:CGRectMake(10, y, w-20, 16)] autorelease];
    statusHeader.text = @"STATUS";
    statusHeader.textColor = [UIColor colorWithWhite:0.6f alpha:1];
    statusHeader.font = [UIFont boldSystemFontOfSize:10];
    statusHeader.backgroundColor = [UIColor clearColor];
    [dash addSubview:statusHeader];
    y += 20;

    /* Status cards */
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *host = [prefs objectForKey:@"gatewayHost"];
    BOOL hasKey = [[prefs objectForKey:@"apiKey"] length] > 0;

    UIView *statusCard = [[[UIView alloc] initWithFrame:CGRectMake(10, y, w-20, 50)] autorelease];
    statusCard.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1f];
    statusCard.layer.cornerRadius = 8;

    UILabel *connLabel = [[[UILabel alloc] initWithFrame:CGRectMake(12, 6, w-44, 18)] autorelease];
    connLabel.text = (host && [host length] > 0) ?
        [NSString stringWithFormat:@"Gateway: %@", host] :
        hasKey ? @"Direct API Mode" : @"Not Configured";
    connLabel.textColor = (host || hasKey) ?
        [UIColor colorWithRed:0.3f green:0.9f blue:0.5f alpha:1] :
        [UIColor colorWithRed:1 green:0.5f blue:0.3f alpha:1];
    connLabel.font = [UIFont boldSystemFontOfSize:14];
    connLabel.backgroundColor = [UIColor clearColor];
    [statusCard addSubview:connLabel];

    UILabel *modelLabel = [[[UILabel alloc] initWithFrame:CGRectMake(12, 26, w-44, 16)] autorelease];
    modelLabel.text = [NSString stringWithFormat:@"Model: %@",
        [prefs objectForKey:@"modelId"] ?: @"claude-sonnet-4-20250514"];
    modelLabel.textColor = [UIColor colorWithWhite:0.7f alpha:1];
    modelLabel.font = [UIFont systemFontOfSize:11];
    modelLabel.backgroundColor = [UIColor clearColor];
    [statusCard addSubview:modelLabel];

    [dash addSubview:statusCard];
    y += 58;

    /* Quick Actions section */
    UILabel *actionsHeader = [[[UILabel alloc] initWithFrame:CGRectMake(10, y, w-20, 16)] autorelease];
    actionsHeader.text = @"QUICK ACTIONS";
    actionsHeader.textColor = [UIColor colorWithWhite:0.6f alpha:1];
    actionsHeader.font = [UIFont boldSystemFontOfSize:10];
    actionsHeader.backgroundColor = [UIColor clearColor];
    [dash addSubview:actionsHeader];
    y += 22;

    /* Action buttons grid - 4 per row */
    NSArray *actions = @[
        @{@"title": @"Ask AI", @"tag": @1},
        @{@"title": @"Open App", @"tag": @2},
        @{@"title": @"Gateway", @"tag": @3},
        @{@"title": @"Settings", @"tag": @4},
        @{@"title": @"Respring", @"tag": @5},
        @{@"title": @"Wi-Fi", @"tag": @6},
        @{@"title": @"Bright+", @"tag": @7},
        @{@"title": @"Bright-", @"tag": @8}
    ];

    CGFloat btnW = (w - 50) / 4;
    CGFloat btnH = 44;
    for (NSUInteger i = 0; i < [actions count]; i++) {
        NSDictionary *act = [actions objectAtIndex:i];
        int col = i % 4;
        int row = i / 4;
        CGFloat bx = 10 + col * (btnW + 10);
        CGFloat by = y + row * (btnH + 8);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(bx, by, btnW, btnH);
        btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12f];
        btn.layer.cornerRadius = 8;
        [btn setTitle:[act objectForKey:@"title"] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:11];
        btn.tag = [[act objectForKey:@"tag"] intValue];
        [btn addTarget:[NSClassFromString(@"SpringBoard") sharedApplication]
               action:@selector(_cpDashAction:)
             forControlEvents:UIControlEventTouchUpInside];
        [dash addSubview:btn];
    }
    y += (btnH + 8) * 2 + 10;

    /* Device Info section */
    UILabel *devHeader = [[[UILabel alloc] initWithFrame:CGRectMake(10, y, w-20, 16)] autorelease];
    devHeader.text = @"DEVICE";
    devHeader.textColor = [UIColor colorWithWhite:0.6f alpha:1];
    devHeader.font = [UIFont boldSystemFontOfSize:10];
    devHeader.backgroundColor = [UIColor clearColor];
    [dash addSubview:devHeader];
    y += 20;

    UIView *devCard = [[[UIView alloc] initWithFrame:CGRectMake(10, y, w-20, 70)] autorelease];
    devCard.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1f];
    devCard.layer.cornerRadius = 8;

    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    float battery = [[UIDevice currentDevice] batteryLevel];
    float brightness = [[UIScreen mainScreen] brightness];

    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);

    NSArray *infoLines = @[
        [NSString stringWithFormat:@"Battery: %.0f%%  |  Brightness: %.0f%%", battery*100, brightness*100],
        [NSString stringWithFormat:@"SpringBoard RAM: %.1f MB", info.resident_size / (1024.0*1024.0)],
        [NSString stringWithFormat:@"%@ - iOS %@", [[UIDevice currentDevice] model],
            [[UIDevice currentDevice] systemVersion]]
    ];

    for (NSUInteger i = 0; i < [infoLines count]; i++) {
        UILabel *line = [[[UILabel alloc] initWithFrame:
            CGRectMake(12, 8 + i*20, w-44, 18)] autorelease];
        line.text = [infoLines objectAtIndex:i];
        line.textColor = [UIColor colorWithWhite:0.8f alpha:1];
        line.font = [UIFont systemFontOfSize:11];
        line.backgroundColor = [UIColor clearColor];
        [devCard addSubview:line];
    }
    [dash addSubview:devCard];

    /* Tap anywhere on dashboard dismisses keyboard if it somehow appeared */
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:dash action:@selector(_cpDismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [dash addGestureRecognizer:tap];
    [tap release];

    return dash;
}

/* Category on UIView for the dashboard keyboard dismiss */
@interface UIView (CPDashboard)
- (void)_cpDismissKeyboard;
@end

@implementation UIView (CPDashboard)
- (void)_cpDismissKeyboard {
    [[UIApplication sharedApplication].keyWindow endEditing:YES];
    /* Also find and resign any search bars */
    for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
        [w endEditing:YES];
    }
}
@end

/*
 * Block the search bar from becoming first responder while dashboard is showing.
 * Hook SBSearchView's keyboard methods.
 */
%hook SBSearchView

- (void)setShowsKeyboard:(BOOL)shows animated:(BOOL)animated {
    if (_dashboardView && shows) return; /* Block keyboard when dashboard is up */
    %orig;
}

- (void)setShowsKeyboard:(BOOL)shows animated:(BOOL)animated shouldDeferResponderStatus:(BOOL)defer {
    if (_dashboardView && shows) return; /* Block keyboard when dashboard is up */
    %orig;
}

- (void)finishBecomingFirstResponderIfNecessary {
    if (_dashboardView) return; /* Block */
    %orig;
}

%end

%hook SBIconController

/*
 * _showSearchKeyboardIfNecessary: is called by SpringBoard when the
 * Spotlight page becomes fully visible after a swipe. This is our
 * reliable hook point.
 */
- (void)_showSearchKeyboardIfNecessary:(BOOL)necessary {
    /* DON'T call %orig — this prevents the keyboard from showing */
    /* Instead, show our dashboard */

    UIView *searchView = nil;
    @try {
        searchView = [self valueForKey:@"_searchView"];
    } @catch (NSException *e) { return; }
    if (!searchView) return;

    /* Remove old dashboard if exists */
    if (_dashboardView) {
        [_dashboardView removeFromSuperview];
        [_dashboardView release];
        _dashboardView = nil;
    }

    /* Build fresh dashboard (refreshes data each time) */
    _dashboardView = [_buildDashboard(searchView.bounds) retain];
    _dashboardView.tag = 44444;
    [searchView addSubview:_dashboardView];
    [searchView bringSubviewToFront:_dashboardView];

    /* Kill keyboard, hide search bar/table/dock */
    [searchView endEditing:YES];
    @try {
        UISearchBar *bar = [searchView valueForKey:@"_searchBar"];
        if (bar) {
            [bar resignFirstResponder];
            bar.hidden = YES;
        }
        UITableView *table = [searchView valueForKey:@"_tableView"];
        if (table) table.hidden = YES;
        UIView *dockContainer = [self valueForKey:@"_dockContainerView"];
        if (dockContainer) {
            [UIView animateWithDuration:0.2 animations:^{
                dockContainer.alpha = 0;
            }];
        }
    } @catch (NSException *e) {}
}

static void _cpRestoreDockAndCleanup(id self_) {
    if (_dashboardView) {
        [_dashboardView removeFromSuperview];
        [_dashboardView release];
        _dashboardView = nil;
    }

    @try {
        UIView *sv = [self_ valueForKey:@"_searchView"];
        if (sv) {
            UISearchBar *bar = [sv valueForKey:@"_searchBar"];
            if (bar) bar.hidden = NO;
            UITableView *table = [sv valueForKey:@"_tableView"];
            if (table) table.hidden = NO;
        }
        UIView *dock = [self_ valueForKey:@"_dockContainerView"];
        if (dock) dock.alpha = 1.0f;
    } @catch (NSException *e) {}
}

- (void)scrollViewDidEndDecelerating:(id)scrollView {
    %orig;
    if (![self isShowingSearch]) _cpRestoreDockAndCleanup(self);
}

- (void)scrollViewDidEndDragging:(id)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    if (!decelerate && ![self isShowingSearch]) _cpRestoreDockAndCleanup(self);
}

- (void)scrollViewDidEndScrollingAnimation:(id)scrollView {
    %orig;
    if (![self isShowingSearch]) _cpRestoreDockAndCleanup(self);
}

%end

/* Dashboard button actions */
%hook SpringBoard

%new
- (void)_cpDashAction:(UIButton *)btn {
    switch (btn.tag) {
        case 1: CPShow(); break; /* Ask AI */
        case 2: [[UIApplication sharedApplication] openURL:
                 [NSURL URLWithString:@"openclaw://"]]; break; /* Open App */
        case 3: notify_post("ai.openclaw.ios6/startGateway"); break; /* Gateway */
        case 4: [[UIApplication sharedApplication] openURL:
                 [NSURL URLWithString:@"prefs:"]]; break; /* Settings - opens Settings.app */
        case 5: { /* Respring */
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Respring?"
                message:nil delegate:self cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
            a.tag = 7777;
            [a show]; [a release];
            break;
        }
        case 6: break; /* WiFi toggle - TODO */
        case 7: { /* Brightness up */
            float b = MIN(1.0f, [[UIScreen mainScreen] brightness] + 0.15f);
            [[UIScreen mainScreen] setBrightness:b];
            break;
        }
        case 8: { /* Brightness down */
            float b = MAX(0.05f, [[UIScreen mainScreen] brightness] - 0.15f);
            [[UIScreen mainScreen] setBrightness:b];
            break;
        }
    }
}

%new
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 7777 && buttonIndex == 1) {
        kill(getpid(), SIGTERM);
    }
}

%end

#pragma mark - Multi-Process Hooks

/*
 * These hooks apply to apps OTHER than SpringBoard.
 * The tweak is now injected into all UIKit processes.
 * We use %ctor to check the bundle ID and only apply relevant hooks.
 */

/*
 * Safari: Add "Ask ClawPod" to action sheets, intercept URL loading
 * for AI-powered page summaries.
 */
%group SafariHooks

%hook BrowserController

- (void)loadURL:(id)url {
    %orig;
    /* Log URL loads - can be used for browsing history AI analysis */
    NSLog(@"[ClawPod/Safari] URL loaded: %@", url);
}

%end

%end /* SafariHooks */

/*
 * MobileSMS: Monitor for replies in the ClawPod chat thread.
 * Auto-detect when user replies and route to the daemon.
 */
%group SMSHooks

%hook CKConversationListController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    /* Notify daemon to check for ClawPod replies */
    notify_post("ai.openclaw.ios6/checkSMSReplies");
}

%end

%end /* SMSHooks */

/*
 * MobileMail: Add "Summarize with ClawPod" option.
 */
%group MailHooks

%hook MFMessageBody

- (id)htmlContent {
    id content = %orig;
    /* Could inject a "Summarize" button here */
    return content;
}

%end

%end /* MailHooks */

/*
 * Music: Show ClawPod status in now playing.
 */
%group MusicHooks
%end

/*
 * Universal hooks (all UIKit apps): add shake-to-ask gesture.
 */
%group UniversalHooks

%hook UIWindow

- (void)motionEnded:(int)motion withEvent:(id)event {
    %orig;
    /* Shake gesture (motion == 1) opens ClawPod in any app */
    if (motion == 1) {
        /* Send notification to SpringBoard to show overlay */
        notify_post("ai.openclaw.ios6/shakeActivate");
    }
}

%end

%end /* UniversalHooks */

#pragma mark - Agentic Launcher (SpringBoard Replacement)

/*
 * Replaces the stock icon grid with CPLauncher.
 * Toggled via "launcherEnabled" in preferences.
 * When enabled, the icon grid is hidden and our launcher view is shown.
 * When disabled, stock SpringBoard works normally.
 */

static UIView *_cpLauncherView = nil;
static BOOL _cpLauncherEnabled = NO;

static void _cpCheckLauncherPref(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    _cpLauncherEnabled = [[prefs objectForKey:@"launcherEnabled"] boolValue];
}

%group LauncherHooks

%hook SBIconController

- (void)viewDidAppear {
    %orig;

    _cpCheckLauncherPref();
    if (!_cpLauncherEnabled) {
        /* Stock mode — make sure launcher is hidden */
        if (_cpLauncherView) _cpLauncherView.hidden = YES;
        return;
    }

    UIView *contentView = [self valueForKey:@"_contentView"];
    if (!contentView) return;

    if (!_cpLauncherView) {
        /* Build the launcher - import dynamically to avoid header issues */
        Class launcherClass = NSClassFromString(@"CPLauncher");
        if (launcherClass) {
            _cpLauncherView = [[launcherClass alloc] initWithFrame:contentView.bounds];
        } else {
            /* Fallback: build a simple launcher inline */
            _cpLauncherView = [[UIView alloc] initWithFrame:contentView.bounds];
            _cpLauncherView.backgroundColor = [UIColor colorWithRed:0.06f green:0.06f blue:0.10f alpha:1.0f];

            UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(16, 40, 288, 30)] autorelease];
            title.text = @"ClawPod Launcher";
            title.textColor = [UIColor whiteColor];
            title.font = [UIFont boldSystemFontOfSize:24];
            title.backgroundColor = [UIColor clearColor];
            [_cpLauncherView addSubview:title];

            UILabel *sub = [[[UILabel alloc] initWithFrame:CGRectMake(16, 72, 288, 20)] autorelease];
            sub.text = @"CPLauncher class not linked. Using fallback.";
            sub.textColor = [UIColor grayColor];
            sub.font = [UIFont systemFontOfSize:12];
            sub.backgroundColor = [UIColor clearColor];
            [_cpLauncherView addSubview:sub];
        }

        [contentView.superview addSubview:_cpLauncherView];
    }

    /* Show launcher, hide stock icons */
    _cpLauncherView.hidden = NO;
    _cpLauncherView.frame = contentView.bounds;
    [contentView.superview bringSubviewToFront:_cpLauncherView];

    /* Refresh launcher data */
    if ([_cpLauncherView respondsToSelector:@selector(refresh)]) {
        [_cpLauncherView performSelector:@selector(refresh)];
    }

    /* Hide stock icon views */
    contentView.hidden = YES;

    /* Hide dock */
    @try {
        UIView *dock = [[self class] instancesRespondToSelector:@selector(dockContainerView)]
            ? [self performSelector:@selector(dockContainerView)] : nil;
        if (!dock) dock = [self valueForKey:@"_dockContainerView"];
        if (dock) dock.hidden = YES;
    } @catch (NSException *e) {}

    /* Hide page dots */
    @try {
        UIView *pageControl = [self valueForKey:@"_pageControl"];
        if (pageControl) pageControl.hidden = YES;
    } @catch (NSException *e) {}
}

%end

%end /* LauncherHooks */

#pragma mark - Constructor

/*
 * Initializes the appropriate hook groups based on which process
 * we've been injected into. This is the Saurik pattern — one dylib,
 * multiple personalities.
 */
%ctor {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];

    if ([bundleId isEqualToString:@"com.apple.springboard"]) {
        /* Initialize all ungrouped hooks (SpringBoard-specific) */
        %init(_ungrouped);
        %init(LauncherHooks);
        _cpCheckLauncherPref();
        NSLog(@"[ClawPod] Loaded in SpringBoard (launcher: %@)",
              _cpLauncherEnabled ? @"ON" : @"OFF");

        /* Listen for shake-activate from other apps */
        int token;
        notify_register_dispatch("ai.openclaw.ios6/shakeActivate", &token,
            dispatch_get_main_queue(), ^(int t) {
                CPShow();
            });

    } else if ([bundleId isEqualToString:@"com.apple.mobilesafari"]) {
        %init(SafariHooks);
        NSLog(@"[ClawPod] Loaded in Safari");

    } else if ([bundleId isEqualToString:@"com.apple.MobileSMS"]) {
        %init(SMSHooks);
        NSLog(@"[ClawPod] Loaded in Messages");

    } else if ([bundleId isEqualToString:@"com.apple.mobilemail"]) {
        %init(MailHooks);
        NSLog(@"[ClawPod] Loaded in Mail");

    } else if ([bundleId isEqualToString:@"com.apple.Music"]) {
        %init(MusicHooks);
        NSLog(@"[ClawPod] Loaded in Music");
    }

    /* Universal hooks for ALL apps (including SpringBoard) */
    %init(UniversalHooks);
    NSLog(@"[ClawPod] Universal hooks loaded in %@", bundleId);
}
