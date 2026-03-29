/*
 * OCChatCell.m
 * LegacyPodClaw - iMessage-style Chat Bubble Cell
 *
 * Blue bubbles for user (right-aligned), light gray for assistant (left-aligned).
 * Matches iOS 6 iMessage appearance. Pure programmatic, no images.
 */

#import "ChatCell.h"

static const CGFloat kBubbleHMargin = 12.0f;
static const CGFloat kBubbleVMargin = 6.0f;
static const CGFloat kBubbleMaxWidthRatio = 0.75f;
static const CGFloat kBubblePadH = 14.0f;
static const CGFloat kBubblePadV = 10.0f;
static const CGFloat kBubbleRadius = 18.0f;
static const CGFloat kFontSize = 15.0f;
static const CGFloat kTimeFontSize = 10.0f;
static const CGFloat kMinBubbleHeight = 36.0f;

@interface OCChatCell () {
    UIView *_bubbleView;
    UILabel *_contentLabel;
    UILabel *_timeLabel;
    OCMessageRole _currentRole;
}
@end

@implementation OCChatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor whiteColor];
        self.contentView.backgroundColor = [UIColor whiteColor];

        _bubbleView = [[UIView alloc] init];
        _bubbleView.layer.cornerRadius = kBubbleRadius;
        _bubbleView.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubbleView];

        _contentLabel = [[UILabel alloc] init];
        _contentLabel.font = [UIFont systemFontOfSize:kFontSize];
        _contentLabel.numberOfLines = 0;
        _contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _contentLabel.backgroundColor = [UIColor clearColor];
        [_bubbleView addSubview:_contentLabel];

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:kTimeFontSize];
        _timeLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        _timeLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_timeLabel];
    }
    return self;
}

- (void)dealloc {
    [_bubbleView release];
    [_contentLabel release];
    [_timeLabel release];
    [super dealloc];
}

- (void)configureWithMessage:(OCMessage *)message {
    _currentRole = message.role;
    BOOL isUser = (message.role == OCMessageRoleUser);

    /* iMessage colors */
    if (isUser) {
        /* iOS 6 iMessage blue */
        _bubbleView.backgroundColor = [UIColor colorWithRed:0.0f green:0.478f blue:1.0f alpha:1.0f];
        _contentLabel.textColor = [UIColor whiteColor];
    } else {
        /* iOS 6 recipient gray-green */
        _bubbleView.backgroundColor = [UIColor colorWithRed:0.89f green:0.90f blue:0.91f alpha:1.0f];
        _contentLabel.textColor = [UIColor blackColor];
    }

    /* Content */
    NSString *text;
    if (message.state == OCMessageStateStreaming) {
        text = message.streamBuffer ? [NSString stringWithString:message.streamBuffer] : @"";
        if ([text length] == 0) text = @"\u2026"; /* ellipsis */
    } else {
        text = message.content ?: @"";
    }
    _contentLabel.text = text;

    /* Time */
    if (message.timestamp) {
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateFormat:@"HH:mm"];
        _timeLabel.text = [fmt stringFromDate:message.timestamp];
    } else {
        _timeLabel.text = @"";
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat cellWidth = self.contentView.bounds.size.width;
    CGFloat maxBubbleWidth = cellWidth * kBubbleMaxWidthRatio;
    CGFloat textMaxWidth = maxBubbleWidth - (kBubblePadH * 2);
    BOOL isUser = (_currentRole == OCMessageRoleUser);

    /* Measure text */
    CGSize textSize = [_contentLabel.text sizeWithFont:_contentLabel.font
                                     constrainedToSize:CGSizeMake(textMaxWidth, CGFLOAT_MAX)
                                         lineBreakMode:NSLineBreakByWordWrapping];

    /* Bubble size */
    CGFloat bubbleW = textSize.width + (kBubblePadH * 2);
    CGFloat bubbleH = MAX(textSize.height + (kBubblePadV * 2), kMinBubbleHeight);

    /* Position bubble - right for user, left for assistant */
    CGFloat bubbleX;
    if (isUser) {
        bubbleX = cellWidth - bubbleW - kBubbleHMargin;
    } else {
        bubbleX = kBubbleHMargin;
    }
    CGFloat bubbleY = kBubbleVMargin;

    _bubbleView.frame = CGRectMake(bubbleX, bubbleY, bubbleW, bubbleH);

    /* Text inside bubble */
    _contentLabel.frame = CGRectMake(kBubblePadH, kBubblePadV,
                                     textSize.width, textSize.height);

    /* Timestamp below bubble */
    CGFloat timeY = bubbleY + bubbleH + 1;
    if (isUser) {
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.frame = CGRectMake(cellWidth - 60 - kBubbleHMargin, timeY, 60, 14);
    } else {
        _timeLabel.textAlignment = NSTextAlignmentLeft;
        _timeLabel.frame = CGRectMake(kBubbleHMargin, timeY, 60, 14);
    }
}

+ (CGFloat)heightForMessage:(OCMessage *)message width:(CGFloat)width {
    CGFloat maxBubbleWidth = width * kBubbleMaxWidthRatio;
    CGFloat textMaxWidth = maxBubbleWidth - (kBubblePadH * 2);

    NSString *text;
    if (message.state == OCMessageStateStreaming) {
        text = message.streamBuffer ? [NSString stringWithString:message.streamBuffer] : @"\u2026";
    } else {
        text = message.content ?: @"";
    }

    CGSize textSize = [text sizeWithFont:[UIFont systemFontOfSize:kFontSize]
                       constrainedToSize:CGSizeMake(textMaxWidth, CGFLOAT_MAX)
                           lineBreakMode:NSLineBreakByWordWrapping];

    CGFloat bubbleH = MAX(textSize.height + (kBubblePadV * 2), kMinBubbleHeight);

    return kBubbleVMargin + bubbleH + 16 + kBubbleVMargin; /* bubble + time + padding */
}

@end
