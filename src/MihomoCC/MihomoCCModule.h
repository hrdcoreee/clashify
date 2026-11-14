#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Forward declaration of ControlCenterUIKit classes for iOS 14 CCSupport
@interface CCUICAPackageDescription : NSObject
@end

@protocol CCUIContentModule <NSObject>
@optional
@property (nonatomic, readonly) UIViewController *contentViewController;
@end

@interface CCUIToggleModule : NSObject <CCUIContentModule>
@property (nonatomic, readonly) UIViewController *contentViewController;
@property (nonatomic, readonly) CCUICAPackageDescription *glyphPackageDescription;
@property (nonatomic, readonly) NSString *glyphState;
@property (nonatomic, copy, readonly) UIImage *iconGlyph;
@property (nonatomic, copy, readonly) UIColor *selectedColor;
@property (nonatomic, copy, readonly) UIImage *selectedIconGlyph;
@property (getter=isSelected, nonatomic) BOOL selected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
@end

// SpringBoardServices private API to toggle the [VPN] icon in the iOS status bar
#ifdef __cplusplus
extern "C" {
#endif
void SBSSetStatusBarShowsVPN(BOOL show);
#ifdef __cplusplus
}
#endif

@interface MihomoCCModule : CCUIToggleModule
@property (nonatomic, assign) BOOL isTunEnabled;
@property (nonatomic, strong) NSTimer *pollTimer;
@end
