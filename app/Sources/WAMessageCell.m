#import "WAMessageCell.h"
#import "WATheme.h"
#import "WAAPI.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPad = 10;
static const CGFloat kTimeH = 14;
static const CGFloat kMedia = 180;

@interface WAMessageCell ()
@property (strong, nonatomic) UIImageView *bubble;
@property (strong, nonatomic) UILabel *label;
@property (strong, nonatomic) UIImageView *media;
@property (strong, nonatomic) UILabel *playLabel;
@property (strong, nonatomic) UILabel *audioLabel;
@property (strong, nonatomic) UILabel *timeLabel;
@end

@implementation WAMessageCell

+ (NSString *)placeholderForMessage:(NSDictionary *)m {
    NSString *kind = m[@"kind"];
    if ([kind isEqualToString:@"sticker"]) return @"[Sticker]";
    if ([kind isEqualToString:@"doc"]) return [NSString stringWithFormat:@"[Document] %@", m[@"text"] ?: @""];
    return m[@"text"] ?: @"";
}

+ (NSString *)durationString:(NSInteger)sec {
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(sec / 60), (long)(sec % 60)];
}

+ (CGSize)contentSizeForMessage:(NSDictionary *)m width:(CGFloat)width {
    NSString *kind = m[@"kind"];
    NSString *text = m[@"text"] ?: @"";
    UIFont *font = [UIFont systemFontOfSize:16];
    if ([kind isEqualToString:@"image"] || [kind isEqualToString:@"video"]) {
        CGFloat h = kMedia;
        if (text.length) {
            CGSize t = [text sizeWithFont:font constrainedToSize:CGSizeMake(kMedia, 2000) lineBreakMode:NSLineBreakByWordWrapping];
            h += 6 + ceil(t.height);
        }
        return CGSizeMake(kMedia, h);
    }
    if ([kind isEqualToString:@"audio"]) return CGSizeMake(170, 30);
    if (![kind isEqualToString:@"text"]) text = [self placeholderForMessage:m];
    CGFloat maxW = floor(width * 0.74) - 2 * kPad;
    CGSize t = [text sizeWithFont:font constrainedToSize:CGSizeMake(maxW, 5000) lineBreakMode:NSLineBreakByWordWrapping];
    return CGSizeMake(MAX(ceil(t.width), 48), MAX(ceil(t.height), 20));
}

+ (CGFloat)heightForMessage:(NSDictionary *)m width:(CGFloat)width {
    return [self contentSizeForMessage:m width:width].height + 26 + 8;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _bubble = [[UIImageView alloc] init];
        [self.contentView addSubview:_bubble];

        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.font = [UIFont systemFontOfSize:16];
        _label.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_label];

        _media = [[UIImageView alloc] init];
        _media.contentMode = UIViewContentModeScaleAspectFill;
        _media.clipsToBounds = YES;
        _media.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1];
        _media.layer.cornerRadius = [WATheme flat] ? 12 : 6;
        [self.contentView addSubview:_media];

        _playLabel = [[UILabel alloc] init];
        _playLabel.text = @"▶";
        _playLabel.textAlignment = NSTextAlignmentCenter;
        _playLabel.textColor = [UIColor whiteColor];
        _playLabel.font = [UIFont systemFontOfSize:40];
        _playLabel.backgroundColor = [UIColor clearColor];
        _playLabel.shadowColor = [UIColor blackColor];
        _playLabel.shadowOffset = CGSizeMake(0, 1);
        [self.contentView addSubview:_playLabel];

        _audioLabel = [[UILabel alloc] init];
        _audioLabel.font = [UIFont systemFontOfSize:18];
        _audioLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_audioLabel];

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:11];
        _timeLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_timeLabel];
    }
    return self;
}

- (void)configureWithMessage:(NSDictionary *)m width:(CGFloat)width playing:(BOOL)playing {
    NSString *mid = m[@"id"];
    self.messageID = mid;
    BOOL mine = [m[@"fromMe"] boolValue];
    NSString *kind = m[@"kind"];
    NSString *text = m[@"text"] ?: @"";

    CGSize cs = [WAMessageCell contentSizeForMessage:m width:width];
    CGFloat bw = MAX(cs.width, 56) + 2 * kPad;
    CGFloat bh = cs.height + 26;
    CGFloat x = mine ? width - bw - 8 : 8;
    CGFloat cx = x + kPad, cy = 4 + 6;

    self.bubble.image = mine ? [WATheme bubbleOut] : [WATheme bubbleIn];
    self.bubble.frame = CGRectMake(x, 4, bw, bh);

    self.label.hidden = YES;
    self.media.hidden = YES;
    self.playLabel.hidden = YES;
    self.audioLabel.hidden = YES;

    if ([kind isEqualToString:@"image"] || [kind isEqualToString:@"video"]) {
        self.media.hidden = NO;
        self.media.image = nil;
        self.media.frame = CGRectMake(cx, cy, kMedia, kMedia);
        if ([kind isEqualToString:@"video"]) {
            self.playLabel.hidden = NO;
            self.playLabel.frame = self.media.frame;
        }
        [WAAPI loadImageForMessageID:mid variant:@"thumb" completion:^(UIImage *img) {
            if (img && [self.messageID isEqualToString:mid]) self.media.image = img;
        }];
        if (text.length) {
            self.label.hidden = NO;
            self.label.text = text;
            self.label.frame = CGRectMake(cx, cy + kMedia + 6, kMedia, cs.height - kMedia - 6);
        }
    } else if ([kind isEqualToString:@"audio"]) {
        self.audioLabel.hidden = NO;
        self.audioLabel.frame = CGRectMake(cx, cy, cs.width, 30);
        self.audioLabel.text = [NSString stringWithFormat:@"%@  Voice  %@",
                                playing ? @"■" : @"▶",
                                [WAMessageCell durationString:[m[@"seconds"] integerValue]]];
    } else {
        self.label.hidden = NO;
        self.label.text = [kind isEqualToString:@"text"] ? text : [WAMessageCell placeholderForMessage:m];
        self.label.frame = CGRectMake(cx, cy, cs.width, cs.height);
    }

    static NSDateFormatter *fmt;
    if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm"; }
    NSTimeInterval ts = [m[@"ts"] doubleValue];
    self.timeLabel.text = ts > 0 ? [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]] : @"";
    self.timeLabel.frame = CGRectMake(x + bw - kPad - 60, 4 + bh - kTimeH - 5, 60, kTimeH);
}

@end
