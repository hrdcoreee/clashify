#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RootViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIButton *coreMenuButton;
@property (nonatomic, assign) BOOL isCoreRunning;

- (void)loadDashboard;
- (void)checkCoreStatus;

@end
