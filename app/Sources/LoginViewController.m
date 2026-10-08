#import "LoginViewController.h"
#import "ChatsViewController.h"
#import "WAAPI.h"
#import "WATheme.h"
#import <QuartzCore/QuartzCore.h>

@interface LoginViewController ()
@property (strong, nonatomic) UIImageView *qrView;
@property (strong, nonatomic) UILabel *hint;
@property (strong, nonatomic) NSTimer *timer;
@property (assign, nonatomic) NSInteger tick;
@property (assign, nonatomic) NSInteger editStep; // 0 = server url, 1 = token
@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WA Legacy";
    self.view.backgroundColor = [WATheme loginBackground];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) self.edgesForExtendedLayout = UIRectEdgeNone;

    CGFloat w = self.view.bounds.size.width;
    self.qrView = [[UIImageView alloc] initWithFrame:CGRectMake((w - 280) / 2, 20, 280, 280)];
    self.qrView.backgroundColor = [UIColor whiteColor];
    self.qrView.layer.cornerRadius = [WATheme flat] ? 0 : 10;
    self.qrView.layer.borderWidth = 1;
    self.qrView.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1].CGColor;
    self.qrView.layer.masksToBounds = YES;
    self.qrView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.qrView];

    self.hint = [[UILabel alloc] initWithFrame:CGRectMake(20, 310, w - 40, 110)];
    self.hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.hint.numberOfLines = 0;
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.font = [UIFont systemFontOfSize:15];
    self.hint.backgroundColor = [UIColor clearColor];
    self.hint.text = @"Connecting to server…";
    [self.view addSubview:self.hint];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Server" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(editServer)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self poll];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

#pragma mark - Polling

- (void)poll {
    [WAAPI getJSON:@"/status" completion:^(id json, NSError *error) {
        if (error) {
            self.qrView.image = nil;
            self.hint.text = [NSString stringWithFormat:@"Can't reach the server:\n%@\n\nTap “Server” to set its address.", error.localizedDescription];
            return;
        }
        NSString *status = json[@"status"];
        if ([status isEqualToString:@"open"]) {
            [self.timer invalidate];
            ChatsViewController *chats = [[ChatsViewController alloc] initWithStyle:UITableViewStylePlain];
            [self.navigationController setViewControllers:@[chats] animated:YES];
        } else if ([status isEqualToString:@"qr"]) {
            self.hint.text = @"On your phone open WhatsApp →\nSettings → Linked devices →\nLink a device, then scan this code.";
            self.tick++;
            if (self.tick % 2 == 1 || !self.qrView.image) [self loadQR];
        } else {
            self.qrView.image = nil;
            self.hint.text = @"Waiting for QR code…";
        }
    }];
}

- (void)loadQR {
    NSURLRequest *req = [NSURLRequest requestWithURL:[WAAPI URLForPath:@"/qr.png"]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:10];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
        UIImage *img = d ? [UIImage imageWithData:d] : nil;
        if (img) self.qrView.image = img;
    }];
}

#pragma mark - Server settings

- (void)editServer {
    self.editStep = 0;
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Bridge server"
                                                message:@"Address, e.g. http://192.168.0.10:3000"
                                               delegate:self cancelButtonTitle:@"Cancel"
                                      otherButtonTitles:@"Next", nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *f = [a textFieldAtIndex:0];
    f.text = [WAAPI serverURL];
    f.keyboardType = UIKeyboardTypeURL;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *text = [alertView textFieldAtIndex:0].text ?: @"";
    if (self.editStep == 0) {
        if (text.length) [WAAPI setServerURL:text];
        self.editStep = 1;
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Access key"
                                                    message:@"BRIDGE_TOKEN from the server (leave empty if none)"
                                                   delegate:self cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *f = [a textFieldAtIndex:0];
        f.text = [WAAPI token];
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        [a show];
    } else {
        [WAAPI setToken:text];
        [self poll];
    }
}

@end
