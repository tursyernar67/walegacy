#import <UIKit/UIKit.h>

/// Full-screen photo viewer with pinch-to-zoom.
@interface WAImageViewController : UIViewController <UIScrollViewDelegate>
- (instancetype)initWithMessageID:(NSString *)mid;
@end
