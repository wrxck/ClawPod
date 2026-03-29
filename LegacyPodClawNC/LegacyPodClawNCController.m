/*
 * LegacyPodClawNCController.m
 * LegacyPodClaw - Notification Center Widget Implementation
 *
 * Shows: connection status, quick ask field, last response snippet.
 * Tap opens the full LegacyPodClaw app.
 * Quick ask sends directly to API and shows response inline.
 */

#import "LegacyPodClawNCController.h"

#define PREFS_PATH @"/var/mobile/Library/Preferences/pro.matthesketh.legacypodclaw.plist"
#define WIDGET_HEIGHT 72.0f
#define EXPANDED_HEIGHT 180.0f

@interface LegacyPodClawNCController () <UITextFieldDelegate> {
    UIView *_view;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_responseLabel;
    UITextField *_quickInput;
    UIButton *_askButton;
    UIActivityIndicatorView *_spinner;
    BOOL _isExpanded;
    BOOL _isProcessing;
    NSURLConnection *_conn;
    NSMutableData *_respData;
    NSMutableString *_sseBuf;
    NSMutableString *_streamBuf;
}
@end

@implementation LegacyPodClawNCController

- (UIView *)view {
    if (!_view) {
        [self _buildView];
    }
    return _view;
}

- (float)viewHeight {
    return _isExpanded ? EXPANDED_HEIGHT : WIDGET_HEIGHT;
}

- (void)_buildView {
    CGFloat w = [[UIScreen mainScreen] bounds].size.width;
    _view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, WIDGET_HEIGHT)];
    _view.backgroundColor = [UIColor clearColor];

    /* Linen-matching background with slight transparency */
    UIView *bg = [[[UIView alloc] initWithFrame:_view.bounds] autorelease];
    bg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3f];
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    bg.layer.cornerRadius = 4;
    bg.layer.masksToBounds = YES;
    [_view addSubview:bg];

    /* Title row */
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, 100, 16)];
    _titleLabel.text = @"LegacyPodClaw";
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:13];
    _titleLabel.backgroundColor = [UIColor clearColor];
    [_view addSubview:_titleLabel];

    /* Status (right-aligned on title row) */
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(w - 140, 4, 130, 16)];
    _statusLabel.textColor = [UIColor colorWithWhite:0.7f alpha:1];
    _statusLabel.font = [UIFont systemFontOfSize:11];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_view addSubview:_statusLabel];

    /* Quick input row */
    _quickInput = [[UITextField alloc] initWithFrame:CGRectMake(10, 24, w - 70, 26)];
    _quickInput.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15f];
    _quickInput.textColor = [UIColor whiteColor];
    _quickInput.font = [UIFont systemFontOfSize:12];
    _quickInput.layer.cornerRadius = 13;
    _quickInput.layer.masksToBounds = YES;
    _quickInput.placeholder = @"Quick ask...";
    _quickInput.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _quickInput.delegate = self;
    _quickInput.returnKeyType = UIReturnKeySend;
    _quickInput.autocorrectionType = UITextAutocorrectionTypeDefault;
    UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 26)] autorelease];
    _quickInput.leftView = pad;
    _quickInput.leftViewMode = UITextFieldViewModeAlways;
    _quickInput.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_view addSubview:_quickInput];

    /* Ask button */
    _askButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _askButton.frame = CGRectMake(w - 52, 24, 42, 26);
    _askButton.backgroundColor = [UIColor colorWithRed:0.92f green:0.30f blue:0.30f alpha:0.9f];
    _askButton.layer.cornerRadius = 13;
    _askButton.layer.masksToBounds = YES;
    [_askButton setTitle:@"Ask" forState:UIControlStateNormal];
    [_askButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _askButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    _askButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_askButton addTarget:self action:@selector(_askTapped) forControlEvents:UIControlEventTouchUpInside];
    [_view addSubview:_askButton];

    /* Spinner (replaces ask button while processing) */
    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.frame = CGRectMake(w - 30, 28, 18, 18);
    _spinner.hidesWhenStopped = YES;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_view addSubview:_spinner];

    /* Response area (shown when expanded) */
    _responseLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 56, w - 20, EXPANDED_HEIGHT - 60)];
    _responseLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1];
    _responseLabel.font = [UIFont systemFontOfSize:12];
    _responseLabel.numberOfLines = 0;
    _responseLabel.backgroundColor = [UIColor clearColor];
    _responseLabel.hidden = YES;
    _responseLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_view addSubview:_responseLabel];
}

- (void)dealloc {
    [_view release]; [_titleLabel release]; [_statusLabel release];
    [_responseLabel release]; [_quickInput release]; [_askButton release];
    [_spinner release]; [_conn release]; [_respData release];
    [_sseBuf release]; [_streamBuf release];
    [super dealloc];
}

#pragma mark - Lifecycle

- (void)viewWillAppear {
    [self _refreshStatus];
}

- (void)viewDidAppear {
    [self _refreshStatus];
}

- (NSURL *)launchURL {
    return [NSURL URLWithString:@"openclaw://"];
}

- (NSURL *)launchURLForTapLocation:(CGPoint)location {
    /* Only launch app if tapping on the title area, not the input */
    if (location.y < 22) {
        return [NSURL URLWithString:@"openclaw://"];
    }
    return nil; /* Don't launch — let the input field handle taps */
}

#pragma mark - Status

- (void)_refreshStatus {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *host = [prefs objectForKey:@"gatewayHost"];
    BOOL hasKey = [[prefs objectForKey:@"apiKey"] length] > 0;

    if (host && [host length] > 0) {
        _statusLabel.text = host;
        _statusLabel.textColor = [UIColor colorWithRed:0.4f green:0.9f blue:0.5f alpha:1];
    } else if (hasKey) {
        _statusLabel.text = @"Direct API";
        _statusLabel.textColor = [UIColor colorWithRed:0.5f green:0.75f blue:1 alpha:1];
    } else {
        _statusLabel.text = @"Not Configured";
        _statusLabel.textColor = [UIColor colorWithRed:1 green:0.5f blue:0.3f alpha:1];
    }
}

#pragma mark - Quick Ask

- (void)_askTapped {
    NSString *q = [_quickInput.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([q length] == 0 || _isProcessing) return;

    [_quickInput resignFirstResponder];
    [self _sendQuery:q];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [self _askTapped];
    return NO;
}

- (void)_sendQuery:(NSString *)query {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSString *apiKey = [prefs objectForKey:@"apiKey"];
    NSString *model = [prefs objectForKey:@"modelId"] ?: @"claude-sonnet-4-20250514";

    if (!apiKey || [apiKey length] == 0) {
        [self _showResponse:@"Set an API key in Settings > LegacyPodClaw"];
        return;
    }

    _isProcessing = YES;
    _askButton.hidden = YES;
    [_spinner startAnimating];

    [_streamBuf release];
    _streamBuf = [[NSMutableString alloc] init];
    [_sseBuf release];
    _sseBuf = [[NSMutableString alloc] init];

    /* Expand to show response */
    [self _expand];

    _responseLabel.text = @"Thinking...";
    _responseLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [req setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];

    NSDictionary *body = @{
        @"model": model,
        @"max_tokens": @(256),
        @"stream": @YES,
        @"system": @"You are Molty, a concise AI in a Notification Center widget. "
                    "Maximum 2-3 sentences. Be extremely brief.",
        @"messages": @[@{@"role": @"user", @"content": query}]
    };
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];

    [_respData release];
    _respData = [[NSMutableData alloc] initWithCapacity:2048];
    [_conn release];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

#pragma mark - Streaming

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
                    _responseLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1];
                    _responseLabel.text = _streamBuf;
                });
            }
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    dispatch_async(dispatch_get_main_queue(), ^{
        _isProcessing = NO;
        _askButton.hidden = NO;
        [_spinner stopAnimating];
        _quickInput.text = @"";
    });
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _showResponse:[NSString stringWithFormat:@"Error: %@", [error localizedDescription]]];
    });
}

#pragma mark - Display

- (void)_showResponse:(NSString *)text {
    _isProcessing = NO;
    _askButton.hidden = NO;
    [_spinner stopAnimating];
    [self _expand];
    _responseLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1];
    _responseLabel.text = text;
}

- (void)_expand {
    if (_isExpanded) return;
    _isExpanded = YES;
    _responseLabel.hidden = NO;

    CGFloat w = _view.bounds.size.width;
    _view.frame = CGRectMake(0, 0, w, EXPANDED_HEIGHT);

    /* Tell NC we changed size */
    id host = nil;
    if ([self respondsToSelector:@selector(host)]) {
        host = [self performSelector:@selector(host)];
    }
    if (host && [host respondsToSelector:@selector(weeAppWantsSizeUpdate:)]) {
        [host performSelector:@selector(weeAppWantsSizeUpdate:) withObject:self];
    }
}

@end
