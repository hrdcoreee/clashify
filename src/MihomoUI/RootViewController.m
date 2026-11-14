#import "RootViewController.h"

static NSString *const kDashboardURL = @"http://127.0.0.1:9090/ui";
static NSString *const kConfigsURL = @"http://127.0.0.1:9090/configs";

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 1. Configure WKWebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:self.webView];

    // Add pull to refresh
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.webView.scrollView.refreshControl = refreshControl;

    // 2. Configure Floating Top-Right TUN Toggle Button
    self.floatingTunButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingTunButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.floatingTunButton.layer.cornerRadius = 18.0;
    self.floatingTunButton.layer.masksToBounds = NO;
    self.floatingTunButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingTunButton.layer.shadowOpacity = 0.25;
    self.floatingTunButton.layer.shadowOffset = CGSizeMake(0, 3);
    self.floatingTunButton.layer.shadowRadius = 4.0;
    self.floatingTunButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    self.floatingTunButton.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);

    [self.floatingTunButton addTarget:self action:@selector(toggleTunTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.floatingTunButton];

    // Auto Layout for floating button (pinned to top-right safe area)
    [NSLayoutConstraint activateConstraints:@[
        [self.floatingTunButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [self.floatingTunButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.floatingTunButton.heightAnchor constraintEqualToConstant:36.0]
    ]];

    [self updateButtonAppearance:NO];
    [self loadDashboard];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self syncTunStatus];
}

- (void)loadDashboard {
    NSURL *url = [NSURL URLWithString:kDashboardURL];
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [self.webView loadRequest:req];
}

- (void)handleRefresh:(UIRefreshControl *)sender {
    [self.webView reload];
    [self syncTunStatus];
    [sender endRefreshing];
}

- (void)updateButtonAppearance:(BOOL)enabled {
    self.isTunEnabled = enabled;
    if (enabled) {
        [self.floatingTunButton setTitle:@"TUN: ON" forState:UIControlStateNormal];
        self.floatingTunButton.backgroundColor = [UIColor systemGreenColor];
        [self.floatingTunButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        [self.floatingTunButton setTitle:@"TUN: OFF" forState:UIControlStateNormal];
        self.floatingTunButton.backgroundColor = [UIColor systemGrayColor];
        [self.floatingTunButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
}

- (void)syncTunStatus {
    NSURL *url = [NSURL URLWithString:kConfigsURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setTimeoutInterval:2.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) return;
            NSError *jsonErr = nil;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if ([dict isKindOfClass:[NSDictionary class]]) {
                BOOL tunOn = [dict[@"tun"][@"enable"] boolValue];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateButtonAppearance:tunOn];
                });
            }
        }];
    [task resume];
}

- (void)toggleTunTapped:(UIButton *)sender {
    BOOL targetState = !self.isTunEnabled;

    // Optimistic UI update
    [self updateButtonAppearance:targetState];

    NSURL *url = [NSURL URLWithString:kConfigsURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"PATCH"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setTimeoutInterval:3.0];

    NSDictionary *body = @{@"tun": @{@"enable": @(targetState)}};
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (error || (httpResp.statusCode != 200 && httpResp.statusCode != 204)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Revert state
                    [self updateButtonAppearance:!targetState];
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mihomo Error"
                                                                                   message:@"Failed to communicate with Mihomo daemon. Ensure root LaunchDaemon is running."
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                });
            }
        }];
    [task resume];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[MihomoUI] WebView failed navigation: %@", error.localizedDescription);
}

@end
