#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
    UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, AVAudioPlayerDelegate>
- (instancetype)initWithJID:(NSString *)jid name:(NSString *)name;
@end
