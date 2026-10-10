#import "ChatViewController.h"
#import "WAAPI.h"
#import "WATheme.h"
#import "WAMessageCell.h"
#import "WAImageViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/MobileCoreServices.h>

static const CGFloat kBarHeight = 48;

static UIImage *ScaledImage(UIImage *img, CGFloat maxSide) {
    CGSize s = img.size;
    CGFloat m = MAX(s.width, s.height);
    if (m <= maxSide) return img;
    CGFloat k = maxSide / m;
    CGSize ns = CGSizeMake(floor(s.width * k), floor(s.height * k));
    UIGraphicsBeginImageContextWithOptions(ns, YES, 1);
    [img drawInRect:CGRectMake(0, 0, ns.width, ns.height)]; // also applies orientation
    UIImage *r = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return r;
}

@interface ChatViewController ()
@property (copy, nonatomic) NSString *jid;
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) UIView *bar;
@property (strong, nonatomic) UITextField *field;
@property (strong, nonatomic) UIButton *attachButton;
@property (strong, nonatomic) UIButton *micButton;
@property (strong, nonatomic) UIButton *sendButton;
@property (strong, nonatomic) NSArray *msgs;
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) AVAudioRecorder *recorder;
@property (strong, nonatomic) NSDate *recordStart;
@property (strong, nonatomic) AVAudioPlayer *player;
@property (copy, nonatomic) NSString *playingID;
@property (assign, nonatomic) NSInteger busyCount;
@end

@implementation ChatViewController

- (instancetype)initWithJID:(NSString *)jid name:(NSString *)name {
    if ((self = [super init])) {
        _jid = [jid copy];
        _msgs = @[];
        self.title = name;
    }
    return self;
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [WATheme background];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) self.edgesForExtendedLayout = UIRectEdgeNone;

    CGRect b = self.view.bounds;
    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, b.size.height - kBarHeight)
                                              style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.backgroundColor = [WATheme background];
    [self.view addSubview:self.table];

    self.bar = [[UIView alloc] initWithFrame:CGRectMake(0, b.size.height - kBarHeight, b.size.width, kBarHeight)];
    self.bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.bar.backgroundColor = [WATheme flat] ? [UIColor colorWithWhite:0.97 alpha:1]
                                              : [UIColor colorWithRed:0.78 green:0.80 blue:0.83 alpha:1];
    [self.view addSubview:self.bar];

    self.attachButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.attachButton.frame = CGRectMake(4, 6, 36, 36);
    self.attachButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.attachButton setTitle:@"+" forState:UIControlStateNormal];
    [self.attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.attachButton];

    self.field = [[UITextField alloc] initWithFrame:CGRectMake(44, 9, b.size.width - 44 - 64, 30)];
    self.field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.field.borderStyle = UITextBorderStyleRoundedRect;
    self.field.placeholder = @"Message";
    self.field.returnKeyType = UIReturnKeySend;
    self.field.delegate = self;
    [self.field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
    [self.bar addSubview:self.field];

    CGRect actionFrame = CGRectMake(b.size.width - 58, 6, 54, 36);

    self.sendButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.sendButton.frame = actionFrame;
    self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton.hidden = YES;
    [self.bar addSubview:self.sendButton];

    self.micButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.micButton.frame = actionFrame;
    self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.micButton setTitle:@"\U0001F3A4" forState:UIControlStateNormal];
    [self.micButton addTarget:self action:@selector(micDown) forControlEvents:UIControlEventTouchDown];
    [self.micButton addTarget:self action:@selector(micUpInside) forControlEvents:UIControlEventTouchUpInside];
    [self.micButton addTarget:self action:@selector(micUpOutside)
             forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.bar addSubview:self.micButton];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
    if (self.isMovingFromParentViewController) [self stopAudio];
}

- (void)fieldChanged {
    BOOL has = self.field.text.length > 0;
    self.sendButton.hidden = !has;
    self.micButton.hidden = has;
}

#pragma mark - Busy indicator / errors

- (void)setBusy:(BOOL)busy {
    self.busyCount += busy ? 1 : -1;
    if (self.busyCount < 0) self.busyCount = 0;
    if (self.busyCount > 0) {
        UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [sp startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)showError:(NSString *)text {
    [[[UIAlertView alloc] initWithTitle:@"Error" message:text delegate:nil
                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

#pragma mark - Keyboard

- (void)keyboardChanged:(NSNotification *)n {
    CGRect kb = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kb = [self.view convertRect:[self.view.window convertRect:kb fromWindow:nil] fromView:nil];
    BOOL show = [n.name isEqualToString:UIKeyboardWillShowNotification];
    CGFloat overlap = show ? MAX(0, CGRectGetMaxY(self.view.bounds) - kb.origin.y) : 0;
    NSTimeInterval dur = [[n.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{
        CGRect b = self.view.bounds;
        self.bar.frame = CGRectMake(0, b.size.height - kBarHeight - overlap, b.size.width, kBarHeight);
        self.table.frame = CGRectMake(0, 0, b.size.width, b.size.height - kBarHeight - overlap);
    }];
    [self scrollToBottom:NO];
}

#pragma mark - Data

- (void)refresh {
    NSString *path = [@"/messages?jid=" stringByAppendingString:[WAAPI escape:self.jid]];
    [WAAPI getJSON:path completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSArray class]]) return;
        NSArray *list = json;
        if ([list isEqual:self.msgs]) return;
        BOOL first = (self.msgs.count == 0);
        BOOL grew = list.count > self.msgs.count;
        self.msgs = list;
        [self.table reloadData];
        if (first || grew) [self scrollToBottom:!first];
    }];
}

- (void)scrollToBottom:(BOOL)animated {
    if (!self.msgs.count) return;
    [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.msgs.count - 1 inSection:0]
                      atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - Sending text

- (void)sendTapped {
    NSString *text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    self.field.text = @"";
    [self fieldChanged];
    [WAAPI sendText:text toJID:self.jid completion:^(id json, NSError *error) {
        if (error) { [self showError:error.localizedDescription]; return; }
        [self refresh];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [self sendTapped];
    return NO;
}

#pragma mark - Sending media

- (void)uploadPath:(NSString *)path kind:(NSString *)kind seconds:(NSInteger)seconds {
    [self setBusy:YES];
    [WAAPI uploadFileAtPath:path kind:kind toJID:self.jid seconds:seconds completion:^(id json, NSError *error) {
        [self setBusy:NO];
        if (error) { [self showError:error.localizedDescription]; return; }
        [self refresh];
    }];
}

- (void)attachTapped {
    [self.field resignFirstResponder];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
        [sheet addButtonWithTitle:@"Take Photo or Video"];
    [sheet addButtonWithTitle:@"Photo & Video Library"];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex) return;
    NSString *title = [sheet buttonTitleAtIndex:index];
    if ([title isEqualToString:@"Take Photo or Video"]) [self openPicker:UIImagePickerControllerSourceTypeCamera];
    else [self openPicker:UIImagePickerControllerSourceTypePhotoLibrary];
}

- (void)openPicker:(UIImagePickerControllerSourceType)type {
    if (![UIImagePickerController isSourceTypeAvailable:type]) return;
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = type;
    NSArray *avail = [UIImagePickerController availableMediaTypesForSourceType:type];
    NSMutableArray *types = [NSMutableArray array];
    NSString *imageType = (__bridge NSString *)kUTTypeImage;
    NSString *movieType = (__bridge NSString *)kUTTypeMovie;
    if ([avail containsObject:imageType]) [types addObject:imageType];
    if ([avail containsObject:movieType]) [types addObject:movieType];
    p.mediaTypes = types;
    p.delegate = self;
    if (type == UIImagePickerControllerSourceTypeCamera) {
        p.videoQuality = UIImagePickerControllerQualityTypeMedium;
        p.videoMaximumDuration = 60;
    }
    [self presentViewController:p animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSString *type = info[UIImagePickerControllerMediaType];
    [self dismissViewControllerAnimated:YES completion:nil];
    if (type && UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeMovie)) {
        NSURL *url = info[UIImagePickerControllerMediaURL];
        if (url) [self uploadPath:url.path kind:@"video" seconds:0];
    } else {
        UIImage *img = info[UIImagePickerControllerOriginalImage];
        if (!img) return;
        NSData *jpg = UIImageJPEGRepresentation(ScaledImage(img, 1280), 0.7);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"photo.jpg"];
        [jpg writeToFile:path atomically:YES];
        [self uploadPath:path kind:@"image" seconds:0];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Voice recording (hold the mic button)

- (void)micDown {
    [self stopAudio];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [session setActive:YES error:nil];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"voice.m4a"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSDictionary *settings = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                               AVSampleRateKey: @22050.0f,
                               AVNumberOfChannelsKey: @1,
                               AVEncoderBitRateKey: @32000};
    self.recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path] settings:settings error:nil];
    if (!self.recorder || ![self.recorder prepareToRecord] || ![self.recorder record]) {
        self.recorder = nil;
        [self showError:@"Can't start recording. Check microphone access."];
        return;
    }
    self.recordStart = [NSDate date];
    self.field.placeholder = @"Recording… release to send";
}

- (void)finishRecordingAndSend:(BOOL)send {
    if (!self.recorder) return;
    NSTimeInterval dur = [[NSDate date] timeIntervalSinceDate:self.recordStart];
    NSString *path = self.recorder.url.path;
    [self.recorder stop];
    self.recorder = nil;
    self.field.placeholder = @"Message";
    if (send && dur >= 1.0) [self uploadPath:path kind:@"audio" seconds:(NSInteger)round(dur)];
}

- (void)micUpInside { [self finishRecordingAndSend:YES]; }
- (void)micUpOutside { [self finishRecordingAndSend:NO]; }

#pragma mark - Playback

- (void)stopAudio {
    [self.player stop];
    self.player = nil;
    if (self.playingID) {
        self.playingID = nil;
        [self.table reloadData];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self stopAudio];
}

- (void)toggleAudio:(NSDictionary *)m {
    NSString *mid = m[@"id"];
    if ([self.playingID isEqualToString:mid]) { [self stopAudio]; return; }
    [self stopAudio];
    [self setBusy:YES];
    [WAAPI downloadMediaForMessageID:mid extension:@"m4a" completion:^(NSString *path, NSError *error) {
        [self setBusy:NO];
        if (error) { [self showError:error.localizedDescription]; return; }
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
        [session setActive:YES error:nil];
        NSError *perr = nil;
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&perr];
        if (!self.player) { [self showError:@"Can't play this voice message"]; return; }
        self.player.delegate = self;
        [self.player play];
        self.playingID = mid;
        [self.table reloadData];
    }];
}

- (void)playVideo:(NSString *)mid {
    [self setBusy:YES];
    [WAAPI prepareMediaForMessageID:mid completion:^(NSError *error) {
        [self setBusy:NO];
        if (error) { [self showError:error.localizedDescription]; return; }
        NSURL *url = [WAAPI URLForPath:[WAAPI mediaPathForMessageID:mid variant:@"full"]];
        MPMoviePlayerViewController *pc = [[MPMoviePlayerViewController alloc] initWithContentURL:url];
        [self presentMoviePlayerViewControllerAnimated:pc];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.msgs.count;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return [WAMessageCell heightForMessage:self.msgs[ip.row] width:tv.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    WAMessageCell *cell = [tv dequeueReusableCellWithIdentifier:@"m"];
    if (!cell) cell = [[WAMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"m"];
    NSDictionary *m = self.msgs[ip.row];
    [cell configureWithMessage:m width:tv.bounds.size.width playing:[self.playingID isEqualToString:m[@"id"]]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    NSDictionary *m = self.msgs[ip.row];
    NSString *kind = m[@"kind"];
    if ([kind isEqualToString:@"image"]) {
        [self.navigationController pushViewController:[[WAImageViewController alloc] initWithMessageID:m[@"id"]] animated:YES];
    } else if ([kind isEqualToString:@"video"]) {
        [self playVideo:m[@"id"]];
    } else if ([kind isEqualToString:@"audio"]) {
        [self toggleAudio:m];
    }
}

@end
