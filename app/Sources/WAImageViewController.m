#import "WAImageViewController.h"
#import "WAAPI.h"

@interface WAImageViewController ()
@property (copy, nonatomic) NSString *mid;
@property (strong, nonatomic) UIScrollView *scroll;
@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation WAImageViewController

- (instancetype)initWithMessageID:(NSString *)mid {
    if ((self = [super init])) { _mid = [mid copy]; self.title = @"Photo"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) self.edgesForExtendedLayout = UIRectEdgeNone;

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.delegate = self;
    self.scroll.minimumZoomScale = 1;
    self.scroll.maximumZoomScale = 4;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.imageView = [[UIImageView alloc] initWithFrame:self.scroll.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scroll addSubview:self.imageView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                    UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    // show the small preview right away, then swap in the full image
    [WAAPI loadImageForMessageID:self.mid variant:@"thumb" completion:^(UIImage *img) {
        if (img && !self.imageView.image) self.imageView.image = img;
    }];
    [WAAPI loadImageForMessageID:self.mid variant:@"full" completion:^(UIImage *img) {
        [self.spinner stopAnimating];
        if (img) self.imageView.image = img;
    }];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
