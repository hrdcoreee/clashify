#import "AppDelegate.h"
#import "RootViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.bgTask = UIBackgroundTaskInvalid;

    // 1. Locate YACD static directory
    NSString *yacdPath = [[NSBundle mainBundle] pathForResource:@"yacd" ofType:nil];
    if (!yacdPath || ![[NSFileManager defaultManager] fileExistsAtPath:yacdPath]) {
        yacdPath = @"/Applications/Mihomo.app/yacd";
    }

    // 2. Start embedded in-process HTTP server on localhost:9091
    self.httpServer = [[HTTPServer alloc] initWithDocumentRoot:yacdPath port:9091];
    [self.httpServer start];

    // 3. Initialize Window & WebView Controller
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    RootViewController *rootVC = [[RootViewController alloc] init];
    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"[MihomoApp] Entered background. Arming 10-second termination timer (no background battery drain)...");

    // Begin short background grace period
    __weak typeof(self) weakSelf = self;
    self.bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [weakSelf stopAndExit];
    }];

    // Strict 10-second timer: automatically kill app and server to guarantee zero background battery usage
    self.terminationTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [weakSelf stopAndExit];
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"[MihomoApp] Returned to foreground within 10 seconds. Cancelling termination timer.");
    if (self.terminationTimer) {
        [self.terminationTimer invalidate];
        self.terminationTimer = nil;
    }
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    NSLog(@"[MihomoApp] Terminating. Stopping embedded HTTP server.");
    [self.httpServer stop];
}

- (void)stopAndExit {
    NSLog(@"[MihomoApp] 10 seconds background elapsed. Terminating process cleanly.");
    [self.httpServer stop];
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    exit(0);
}

@end
