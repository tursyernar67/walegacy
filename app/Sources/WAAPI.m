#import "WAAPI.h"

static NSString *const kServerKey = @"WAServerURL";
static NSString *const kTokenKey = @"WAToken";

@implementation WAAPI

#pragma mark - Settings

+ (NSString *)serverURL {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kServerKey];
    return s.length ? s : @"http://192.168.0.10:3000";
}

+ (void)setServerURL:(NSString *)url {
    NSString *clean = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([clean hasSuffix:@"/"]) clean = [clean substringToIndex:clean.length - 1];
    [[NSUserDefaults standardUserDefaults] setObject:clean forKey:kServerKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)token {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kTokenKey] ?: @"";
}

+ (void)setToken:(NSString *)token {
    [[NSUserDefaults standardUserDefaults] setObject:token ?: @"" forKey:kTokenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - URLs

+ (NSString *)escape:(NSString *)s {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)s, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
}

+ (NSURL *)URLForPath:(NSString *)path {
    NSString *full = [[self serverURL] stringByAppendingString:path];
    NSString *key = [self escape:[self token]];
    if (key.length) {
        full = [full stringByAppendingString:([full rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&")];
        full = [full stringByAppendingFormat:@"key=%@", key];
    }
    return [NSURL URLWithString:full];
}

+ (NSError *)errorWithText:(NSString *)text {
    return [NSError errorWithDomain:@"WALegacy" code:1 userInfo:@{NSLocalizedDescriptionKey: text}];
}

#pragma mark - JSON

+ (void)run:(NSURLRequest *)req completion:(WAJSONCompletion)completion {
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        if (err || !data) { completion(nil, err ?: [self errorWithText:@"No response"]); return; }
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
        if (code == 401) { completion(nil, [self errorWithText:@"Wrong access key"]); return; }
        NSError *jerr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
        if (jerr || !json) { completion(nil, jerr ?: [self errorWithText:@"Bad response"]); return; }
        if (code >= 400) {
            NSString *msg = [json isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
            completion(nil, [self errorWithText:msg ?: @"Server error"]);
            return;
        }
        completion(json, nil);
    }];
}

+ (void)getJSON:(NSString *)path completion:(WAJSONCompletion)completion {
    NSURLRequest *req = [NSURLRequest requestWithURL:[self URLForPath:path]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:15];
    [self run:req completion:completion];
}

+ (void)sendText:(NSString *)text toJID:(NSString *)jid completion:(WAJSONCompletion)completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/send"]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:20];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"jid": jid, @"text": text} options:0 error:nil];
    [self run:req completion:completion];
}

#pragma mark - Media

+ (NSString *)mediaPathForMessageID:(NSString *)mid variant:(NSString *)variant {
    return [NSString stringWithFormat:@"/media?id=%@&v=%@", [self escape:mid], variant];
}

+ (NSString *)cacheDir {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    NSString *dir = [base stringByAppendingPathComponent:@"wa"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSString *)safeName:(NSString *)s {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_';
        [out appendFormat:@"%C", ok ? c : (unichar)'_'];
    }
    return out;
}

+ (NSCache *)imageCache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 80; });
    return cache;
}

+ (void)fetchData:(NSString *)path timeout:(NSTimeInterval)timeout completion:(void (^)(NSData *data, NSError *error))completion {
    NSURLRequest *req = [NSURLRequest requestWithURL:[self URLForPath:path]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:timeout];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
        if (err || !data || code >= 400) {
            completion(nil, err ?: [self errorWithText:(code == 401 ? @"Wrong access key" : @"Media unavailable")]);
            return;
        }
        completion(data, nil);
    }];
}

+ (void)loadImageForMessageID:(NSString *)mid variant:(NSString *)variant completion:(void (^)(UIImage *image))completion {
    NSString *key = [NSString stringWithFormat:@"%@_%@", variant, [self safeName:mid]];
    UIImage *mem = [[self imageCache] objectForKey:key];
    if (mem) { completion(mem); return; }

    NSString *file = [[self cacheDir] stringByAppendingPathComponent:[key stringByAppendingString:@".jpg"]];
    UIImage *disk = [UIImage imageWithContentsOfFile:file];
    if (disk) { [[self imageCache] setObject:disk forKey:key]; completion(disk); return; }

    [self fetchData:[self mediaPathForMessageID:mid variant:variant]
            timeout:([variant isEqualToString:@"full"] ? 90 : 30)
         completion:^(NSData *data, NSError *error) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (img) {
            [data writeToFile:file atomically:YES];
            [[self imageCache] setObject:img forKey:key];
        }
        completion(img);
    }];
}

+ (void)prepareMediaForMessageID:(NSString *)mid completion:(void (^)(NSError *error))completion {
    [self fetchData:[NSString stringWithFormat:@"/prepare?id=%@", [self escape:mid]]
            timeout:240
         completion:^(NSData *data, NSError *error) { completion(error); }];
}

+ (void)downloadMediaForMessageID:(NSString *)mid extension:(NSString *)ext completion:(void (^)(NSString *path, NSError *error))completion {
    NSString *file = [[self cacheDir] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"full_%@.%@", [self safeName:mid], ext]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:file]) { completion(file, nil); return; }
    [self fetchData:[self mediaPathForMessageID:mid variant:@"full"] timeout:240 completion:^(NSData *data, NSError *error) {
        if (!data) { completion(nil, error); return; }
        [data writeToFile:file atomically:YES];
        completion(file, nil);
    }];
}

+ (void)uploadFileAtPath:(NSString *)path kind:(NSString *)kind toJID:(NSString *)jid seconds:(NSInteger)seconds completion:(WAJSONCompletion)completion {
    NSData *body = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!body) { completion(nil, [self errorWithText:@"Can't read the file"]); return; }
    NSString *p = [NSString stringWithFormat:@"/send-media?jid=%@&kind=%@&seconds=%ld", [self escape:jid], kind, (long)seconds];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[self URLForPath:p]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:240];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = body;
    [self run:req completion:completion];
}

@end
