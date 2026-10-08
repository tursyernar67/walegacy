#import <UIKit/UIKit.h>

typedef void (^WAJSONCompletion)(id json, NSError *error);

/// Client for the WA Legacy bridge (see /bridge).
@interface WAAPI : NSObject

+ (NSString *)serverURL;
+ (void)setServerURL:(NSString *)url;
+ (NSString *)token;
+ (void)setToken:(NSString *)token;

/// Percent-escapes a string for use inside a query parameter.
+ (NSString *)escape:(NSString *)s;

/// Full URL (including the access key) for a bridge path such as /qr.png.
+ (NSURL *)URLForPath:(NSString *)path;

+ (void)getJSON:(NSString *)path completion:(WAJSONCompletion)completion;
+ (void)sendText:(NSString *)text toJID:(NSString *)jid completion:(WAJSONCompletion)completion;

/// Bridge path for a media message. variant is @"thumb" or @"full".
+ (NSString *)mediaPathForMessageID:(NSString *)mid variant:(NSString *)variant;

/// Cached (memory + disk) image loader. Calls back on the main queue, image is nil on failure.
+ (void)loadImageForMessageID:(NSString *)mid variant:(NSString *)variant completion:(void (^)(UIImage *image))completion;

/// Asks the bridge to download/convert a message's media. Can take a while for video.
+ (void)prepareMediaForMessageID:(NSString *)mid completion:(void (^)(NSError *error))completion;

/// Downloads full media to the local cache and returns the file path.
+ (void)downloadMediaForMessageID:(NSString *)mid extension:(NSString *)ext completion:(void (^)(NSString *path, NSError *error))completion;

/// Uploads a local file. kind is @"image", @"video" or @"audio".
+ (void)uploadFileAtPath:(NSString *)path kind:(NSString *)kind toJID:(NSString *)jid seconds:(NSInteger)seconds completion:(WAJSONCompletion)completion;

@end
