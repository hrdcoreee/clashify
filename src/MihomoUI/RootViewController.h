#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RootViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIButton *floatingTunButton;
@property (nonatomic, assign) BOOL isTunEnabled;
@end
