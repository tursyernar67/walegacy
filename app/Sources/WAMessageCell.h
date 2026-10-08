#import <UIKit/UIKit.h>

/// One chat bubble: text, photo, video, voice message, or a placeholder.
@interface WAMessageCell : UITableViewCell

@property (copy, nonatomic) NSString *messageID;

- (void)configureWithMessage:(NSDictionary *)message width:(CGFloat)width playing:(BOOL)playing;
+ (CGFloat)heightForMessage:(NSDictionary *)message width:(CGFloat)width;

@end
