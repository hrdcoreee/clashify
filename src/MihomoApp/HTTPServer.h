#import <Foundation/Foundation.h>

@interface HTTPServer : NSObject

@property (nonatomic, assign, readonly) uint16_t port;
@property (nonatomic, copy, readonly) NSString *documentRoot;
@property (nonatomic, assign, readonly) BOOL isRunning;

- (instancetype)initWithDocumentRoot:(NSString *)documentRoot port:(uint16_t)port;
- (BOOL)start;
- (void)stop;

@end
