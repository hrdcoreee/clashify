#import "MihomoCCModule.h"

static NSString *const kMihomoConfigsURL = @"http://127.0.0.1:9090/configs";

@implementation MihomoCCModule

- (instancetype)init {
    if ((self = [super init])) {
        _isTunEnabled = NO;
        [self checkCurrentTunStatus];
    }
    return self;
}

- (BOOL)isSelected {
    return _isTunEnabled;
}

- (void)setSelected:(BOOL)selected {
    _isTunEnabled = selected;

    // Instantly update SpringBoard VPN status bar indicator
    if (&SBSSetStatusBarShowsVPN != NULL) {
        SBSSetStatusBarShowsVPN(selected);
    }

    // Refresh CCUI toggle state immediately for smooth UI feedback
    [self refreshState];

    // Send asynchronous HTTP PATCH request to Mihomo REST API
    NSURL *url = [NSURL URLWithString:kMihomoConfigsURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"PATCH"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setTimeoutInterval:3.0];

    NSDictionary *payload = @{
        @"tun": @{
            @"enable": @(selected)
        }
    };

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError) {
        NSLog(@"[MihomoCC] JSON serialization error: %@", jsonError);
        return;
    }
    [request setHTTPBody:bodyData];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (error || (httpResp.statusCode != 200 && httpResp.statusCode != 204)) {
                NSLog(@"[MihomoCC] Failed to PATCH TUN state: %@", error ?: [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                // Re-sync with actual daemon state in case of failure
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self checkCurrentTunStatus];
                });
            } else {
                NSLog(@"[MihomoCC] Successfully set TUN enable: %d", selected);
            }
        }];
    [task resume];
}

- (void)checkCurrentTunStatus {
    NSURL *url = [NSURL URLWithString:kMihomoConfigsURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:2.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.isTunEnabled) {
                        self.isTunEnabled = NO;
                        if (&SBSSetStatusBarShowsVPN != NULL) {
                            SBSSetStatusBarShowsVPN(NO);
                        }
                        [self refreshState];
                    }
                });
                return;
            }

            NSError *jsonErr = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)json;
                NSDictionary *tunDict = dict[@"tun"];
                if ([tunDict isKindOfClass:[NSDictionary class]]) {
                    BOOL enabled = [tunDict[@"enable"] boolValue];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.isTunEnabled != enabled) {
                            self.isTunEnabled = enabled;
                            if (&SBSSetStatusBarShowsVPN != NULL) {
                                SBSSetStatusBarShowsVPN(enabled);
                            }
                            [self refreshState];
                        }
                    });
                }
            }
        }];
    [task resume];
}

- (UIImage *)iconGlyph {
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:@"shield.lefthalf.fill"];
        if (img) return img;
        return [UIImage systemImageNamed:@"network"];
    }
    return [UIImage imageNamed:@"icon" inBundle:[NSBundle bundleForClass:[self class]] compatibleWithTraitCollection:nil];
}

- (UIImage *)selectedIconGlyph {
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:@"shield.fill"];
        if (img) return img;
        return [UIImage systemImageNamed:@"network"];
    }
    return [self iconGlyph];
}

- (UIColor *)selectedColor {
    // Elegant iOS System Blue or Green for VPN active
    return [UIColor systemGreenColor];
}

@end
