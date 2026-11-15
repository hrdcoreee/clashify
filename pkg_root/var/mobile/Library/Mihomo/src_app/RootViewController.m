#import "RootViewController.h"
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/stat.h>

extern char **environ;

static NSString *const kYacdURL = @"http://127.0.0.1:9091/?hostname=127.0.0.1&port=9090";
static NSString *const kCoreAPI = @"http://127.0.0.1:9090";
static NSString *const kRootPasswordKey = @"MihomoRootSSHPassword";

static int run_cmd(const char *cmd) {
    pid_t pid;
    const char *custom_env[] = {
        "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME=/var/mobile",
        "TMPDIR=/tmp",
        NULL
    };
    const char *argv[] = {"/bin/sh", "-c", cmd, NULL};
    int status = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)argv, (char *const *)custom_env);
    if (status == 0) {
        int waitStatus = 0;
        waitpid(pid, &waitStatus, 0);
        return WEXITSTATUS(waitStatus);
    }
    return -1;
}

static void run_root_command(const char *command, NSString *password) {
    // 1. Elevate to root directly if SUID bit is set
    setuid(0);
    setgid(0);
    if (getuid() == 0 || geteuid() == 0) {
        run_cmd(command);
        return;
    }

    // 2. Try SUID helper if available
    if (access("/usr/local/bin/mihomo-suid-helper", X_OK) == 0) {
        char helperCmd[1024];
        snprintf(helperCmd, sizeof(helperCmd), "/usr/local/bin/mihomo-suid-helper %s", command);
        if (run_cmd(helperCmd) == 0) {
            return;
        }
    }

    // 3. Fallback to SSH via localhost
    if (!password || password.length == 0) {
        password = @"alpine";
    }

    if (access("/var/mobile/.ssh/id_mihomo", R_OK) == 0) {
        char sshKeyCmd[2048];
        snprintf(sshKeyCmd, sizeof(sshKeyCmd),
                 "/usr/bin/ssh -i /var/mobile/.ssh/id_mihomo -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 root@127.0.0.1 \"%s\" > /var/mobile/Library/Mihomo/app_cmd.log 2>&1",
                 command);
        if (run_cmd(sshKeyCmd) == 0) {
            return;
        }
    }

    NSString *askpassFile = @"/var/mobile/Library/Mihomo/.askpass.sh";
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\necho '%@'\n", password];
    [script writeToFile:askpassFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([askpassFile UTF8String], 0755);

    char fullCmd[2048];
    snprintf(fullCmd, sizeof(fullCmd),
             "SSH_ASKPASS='%s' SSH_ASKPASS_REQUIRE=force DISPLAY=:0 /usr/bin/ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@127.0.0.1 \"%s\" > /var/mobile/Library/Mihomo/app_cmd.log 2>&1",
             [askpassFile UTF8String], command);
    run_cmd(fullCmd);
    unlink([askpassFile UTF8String]);
}

@interface RootViewController ()
@property (nonatomic, strong) NSTimer *statusTimer;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // 1. Configure Fullscreen WKWebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:self.webView];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.webView.scrollView.refreshControl = refresh;

    // 2. Configure Bottom Floating Core Control Menu Button
    self.coreMenuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.coreMenuButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.coreMenuButton.layer.cornerRadius = 18.0;
    self.coreMenuButton.layer.masksToBounds = NO;
    self.coreMenuButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.coreMenuButton.layer.shadowOpacity = 0.5;
    self.coreMenuButton.layer.shadowOffset = CGSizeMake(0, 3);
    self.coreMenuButton.layer.shadowRadius = 6.0;
    self.coreMenuButton.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.coreMenuButton.contentEdgeInsets = UIEdgeInsetsMake(8, 18, 8, 18);
#pragma clang diagnostic pop
    [self.coreMenuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    [self.coreMenuButton addTarget:self action:@selector(coreMenuTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.coreMenuButton];

    // Align to BOTTOM center in safe area
    [NSLayoutConstraint activateConstraints:@[
        [self.coreMenuButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14.0],
        [self.coreMenuButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.coreMenuButton.heightAnchor constraintEqualToConstant:38.0]
    ]];

    [self updateButtonAppearance:NO];
    [self loadDashboard];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self checkCoreStatus];
    [self autoStartCoreIfNeeded];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.5
                                                        target:self
                                                      selector:@selector(checkCoreStatus)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)loadDashboard {
    NSURL *url = [NSURL URLWithString:kYacdURL];
    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:4.0];
    [self.webView loadRequest:req];
}

- (void)handleRefresh:(UIRefreshControl *)sender {
    [self.webView reload];
    [self checkCoreStatus];
    [sender endRefreshing];
}

- (void)checkCoreStatus {
    NSURL *url = [NSURL URLWithString:kCoreAPI];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 1.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            BOOL running = (httpResp != nil && (httpResp.statusCode == 200 || httpResp.statusCode == 404));
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateButtonAppearance:running];
            });
        }];
    [task resume];
}

- (void)updateButtonAppearance:(BOOL)running {
    self.isCoreRunning = running;
    if (running) {
        [self.coreMenuButton setTitle:@"🟢 Core: ON" forState:UIControlStateNormal];
        self.coreMenuButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.26 blue:0.16 alpha:0.94];
    } else {
        [self.coreMenuButton setTitle:@"🔴 Core: OFF" forState:UIControlStateNormal];
        self.coreMenuButton.backgroundColor = [UIColor colorWithRed:0.38 green:0.12 blue:0.12 alpha:0.94];
    }
}

- (void)coreMenuTapped:(UIButton *)sender {
    NSString *savedPass = [[NSUserDefaults standardUserDefaults] stringForKey:kRootPasswordKey];
    if (!savedPass) {
        [self promptForRootPassword];
        return;
    }
    [self showActionSheet:sender];
}

- (void)promptForRootPassword {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Root Password"
                                                                   message:@"Enter root SSH password to control the daemon (default: alpine):"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"alpine";
        textField.text = @"alpine";
        textField.secureTextEntry = YES;
    }];

    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
        NSString *pass = alert.textFields.firstObject.text;
        if (pass.length == 0) pass = @"alpine";
        [[NSUserDefaults standardUserDefaults] setObject:pass forKey:kRootPasswordKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self showActionSheet:self.coreMenuButton];
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];

    [alert addAction:saveAction];
    [alert addAction:cancelAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showActionSheet:(UIButton *)sender {
    NSString *statusStr = self.isCoreRunning ? @"Core status: Running" : @"Core status: Stopped";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clashify Core Control"
                                                                   message:statusStr
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *startAction = [UIAlertAction actionWithTitle:@"🚀 Start Core"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
        [self executeStart];
    }];

    UIAlertAction *stopAction = [UIAlertAction actionWithTitle:@"🛑 Force Stop (killall)"
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(UIAlertAction *action) {
        [self executeStop];
    }];

    UIAlertAction *restartAction = [UIAlertAction actionWithTitle:@"🔄 Restart Core"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
        [self executeRestart];
    }];

    UIAlertAction *changePassAction = [UIAlertAction actionWithTitle:@"🔑 Change Root Password"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *action) {
        [self promptForRootPassword];
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];

    [alert addAction:startAction];
    [alert addAction:stopAction];
    [alert addAction:restartAction];
    [alert addAction:changePassAction];
    [alert addAction:cancelAction];

    alert.popoverPresentationController.sourceView = sender;
    alert.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)autoStartCoreIfNeeded {
    NSURL *url = [NSURL URLWithString:kCoreAPI];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 0.8;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            BOOL running = (httpResp != nil && (httpResp.statusCode == 200 || httpResp.statusCode == 404));
            if (!running) {
                NSLog(@"[MihomoApp] Core is not active, starting background daemon...");
                [self executeStart];
            }
        }];
    [task resume];
}

- (void)executeStart {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        setuid(0);
        setgid(0);
        run_cmd("/usr/local/bin/mihomo-ctl start");
        sleep(1);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkCoreStatus];
            [self.webView reload];
        });
    });
}

- (void)executeStop {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        setuid(0);
        setgid(0);
        run_cmd("/usr/local/bin/mihomo-ctl stop");
        sleep(1);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkCoreStatus];
        });
    });
}

- (void)executeRestart {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        setuid(0);
        setgid(0);
        run_cmd("/usr/local/bin/mihomo-ctl restart");
        sleep(1);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkCoreStatus];
            [self.webView reload];
        });
    });
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
