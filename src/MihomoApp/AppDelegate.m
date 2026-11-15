#import "AppDelegate.h"
#import "RootViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Locate YACD static directory
    NSString *yacdPath = [[NSBundle mainBundle] pathForResource:@"yacd" ofType:nil];
    if (!yacdPath || ![[NSFileManager defaultManager] fileExistsAtPath:yacdPath]) {
        yacdPath = @"/Applications/Mihomo.app/yacd";
    }

    // 2. Start embedded HTTP server on localhost:9091 for dashboard UI
    self.httpServer = [[HTTPServer alloc] initWithDocumentRoot:yacdPath port:9091];
    [self.httpServer start];

    // 3. Initialize Window & View Controller
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    RootViewController *rootVC = [[RootViewController alloc] init];
    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // App minimized: pause local UI server to save battery
    [self.httpServer stop];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // App foregrounded: resume local UI server and refresh status
    if (!self.httpServer.isRunning) {
        [self.httpServer start];
    }
    if ([self.window.rootViewController isKindOfClass:[RootViewController class]]) {
        RootViewController *vc = (RootViewController *)self.window.rootViewController;
        [vc loadDashboard];
        [vc checkCoreStatus];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // App closing: stop local UI server.
    // NEVER touch the core! Core runs as an independent system daemon.
    [self.httpServer stop];
}

@end
