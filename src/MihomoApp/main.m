#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#include <unistd.h>

int main(int argc, char *argv[]) {
    // Elevate to root if SUID bit (chmod 4755) is set on binary
    setuid(0);
    setgid(0);

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
