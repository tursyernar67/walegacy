#import "WATheme.h"
#import <QuartzCore/QuartzCore.h>

@implementation WATheme

+ (BOOL)flat {
    static BOOL flat;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ flat = [[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0; });
    return flat;
}

+ (UIColor *)accent {
    return [self flat] ? [UIColor colorWithRed:0.07 green:0.62 blue:0.35 alpha:1]
                       : [UIColor colorWithRed:0.20 green:0.36 blue:0.33 alpha:1];
}

+ (UIColor *)background {
    return [self flat] ? [UIColor colorWithRed:0.94 green:0.93 blue:0.91 alpha:1]
                       : [UIColor colorWithRed:0.86 green:0.82 blue:0.74 alpha:1];
}

+ (UIColor *)loginBackground {
    return [self flat] ? [UIColor whiteColor] : [UIColor groupTableViewBackgroundColor];
}

+ (UIImage *)bubbleWithTop:(UIColor *)top bottom:(UIColor *)bottom border:(UIColor *)border {
    CGFloat s = 36;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(CGRectMake(0, 0, s, s), 1, 1);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:[self flat] ? 17 : 13];
    CGContextSaveGState(ctx);
    [path addClip];
    if ([self flat]) {
        [top setFill];
        UIRectFill(CGRectMake(0, 0, s, s));
    } else {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSArray *cols = @[(id)top.CGColor, (id)bottom.CGColor];
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, 0), CGPointMake(0, s), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);
    }
    CGContextRestoreGState(ctx);
    if (![self flat] && border) {
        [border setStroke];
        path.lineWidth = 1;
        [path stroke];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(16, 16, 16, 16)];
}

+ (UIImage *)bubbleOut {
    static UIImage *img;
    if (!img) {
        img = [self bubbleWithTop:([self flat] ? [UIColor colorWithRed:0.86 green:0.97 blue:0.78 alpha:1]
                                               : [UIColor colorWithRed:0.87 green:0.97 blue:0.75 alpha:1])
                           bottom:[UIColor colorWithRed:0.75 green:0.90 blue:0.60 alpha:1]
                           border:[UIColor colorWithRed:0.55 green:0.72 blue:0.42 alpha:1]];
    }
    return img;
}

+ (UIImage *)bubbleIn {
    static UIImage *img;
    if (!img) {
        img = [self bubbleWithTop:[UIColor whiteColor]
                           bottom:[UIColor colorWithWhite:0.92 alpha:1]
                           border:[UIColor colorWithWhite:0.65 alpha:1]];
    }
    return img;
}

+ (UIImage *)avatarForName:(NSString *)name {
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    NSArray *colors = @[
        [UIColor colorWithRed:0.07 green:0.62 blue:0.35 alpha:1],
        [UIColor colorWithRed:0.25 green:0.50 blue:0.80 alpha:1],
        [UIColor colorWithRed:0.80 green:0.45 blue:0.20 alpha:1],
        [UIColor colorWithRed:0.60 green:0.35 blue:0.70 alpha:1],
        [UIColor colorWithRed:0.75 green:0.30 blue:0.35 alpha:1],
        [UIColor colorWithRed:0.35 green:0.60 blue:0.60 alpha:1]];
    CGFloat s = 44;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [colors[name.hash % colors.count] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, s, s)] fill];
    UIFont *font = [UIFont boldSystemFontOfSize:20];
    CGSize ts = [letter sizeWithFont:font];
    [[UIColor whiteColor] set];
    [letter drawAtPoint:CGPointMake((s - ts.width) / 2, (s - ts.height) / 2) withFont:font];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    bar.tintColor = [self accent];
    if ([self flat]) bar.barTintColor = [UIColor colorWithWhite:0.98 alpha:1];
}

@end
