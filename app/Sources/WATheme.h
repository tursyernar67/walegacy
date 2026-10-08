#import <UIKit/UIKit.h>

/// Visual style: skeuomorphic on iOS 6, flat and minimal on iOS 7+.
@interface WATheme : NSObject

+ (BOOL)flat;
+ (UIColor *)accent;
+ (UIColor *)background;
+ (UIColor *)loginBackground;
+ (UIImage *)bubbleOut;
+ (UIImage *)bubbleIn;
+ (UIImage *)avatarForName:(NSString *)name;
+ (void)styleNavigationBar:(UINavigationBar *)bar;

@end
