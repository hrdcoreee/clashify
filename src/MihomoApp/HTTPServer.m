#import "HTTPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>

@interface HTTPServer ()
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation HTTPServer

- (instancetype)initWithDocumentRoot:(NSString *)documentRoot port:(uint16_t)port {
    self = [super init];
    if (self) {
        _documentRoot = [documentRoot copy];
        _port = port;
        _serverSocket = -1;
        _isRunning = NO;
        _serverQueue = dispatch_queue_create("com.hrdcoreee.clashify.httpserver", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)start {
    if (self.isRunning) return YES;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        NSLog(@"[HTTPServer] socket() failed: %s", strerror(errno));
        return NO;
    }

    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1"); // Only listen on localhost

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[HTTPServer] bind() failed on port %d: %s", self.port, strerror(errno));
        close(sock);
        return NO;
    }

    if (listen(sock, 32) < 0) {
        NSLog(@"[HTTPServer] listen() failed: %s", strerror(errno));
        close(sock);
        return NO;
    }

    self.serverSocket = sock;
    self.isRunning = YES;
    NSLog(@"[HTTPServer] Serving %@ at http://127.0.0.1:%d", self.documentRoot, self.port);

    dispatch_async(self.serverQueue, ^{
        [self acceptConnectionsLoop];
    });

    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    self.isRunning = NO;
    if (self.serverSocket >= 0) {
        // Shutdown and close socket to wake accept()
        shutdown(self.serverSocket, SHUT_RDWR);
        close(self.serverSocket);
        self.serverSocket = -1;
    }
    NSLog(@"[HTTPServer] Stopped.");
}

- (void)acceptConnectionsLoop {
    while (self.isRunning && self.serverSocket >= 0) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(self.serverSocket, (struct sockaddr *)&clientAddr, &clientLen);

        if (clientSock < 0) {
            if (!self.isRunning) break;
            continue;
        }

        // Handle connection on a concurrent queue using standard POSIX read/write (NO sendfile!)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSock];
        });
    }
}

- (void)handleClient:(int)fd {
    char reqBuf[2048] = {0};
    ssize_t bytesRead = read(fd, reqBuf, sizeof(reqBuf) - 1);
    if (bytesRead <= 0) {
        close(fd);
        return;
    }

    // Parse HTTP request line: GET /path HTTP/1.1
    char method[16] = {0};
    char rawPath[1024] = {0};
    if (sscanf(reqBuf, "%15s %1023s", method, rawPath) != 2 || strcmp(method, "GET") != 0) {
        const char *resp = "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n";
        write(fd, resp, strlen(resp));
        close(fd);
        return;
    }

    // Strip query string (e.g. ?hostname=127.0.0.1)
    char *query = strchr(rawPath, '?');
    if (query) *query = '\0';

    NSString *relPath = [NSString stringWithUTF8String:rawPath];
    if ([relPath isEqualToString:@"/"] || relPath.length == 0) {
        relPath = @"/index.html";
    }

    // Prevent directory traversal
    if ([relPath containsString:@".."]) {
        const char *resp = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n";
        write(fd, resp, strlen(resp));
        close(fd);
        return;
    }

    NSString *fullPath = [self.documentRoot stringByAppendingPathComponent:relPath];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] || isDir) {
        // Try fallback to index.html for SPA routing
        fullPath = [self.documentRoot stringByAppendingPathComponent:@"index.html"];
    }

    FILE *f = fopen([fullPath UTF8String], "rb");
    if (!f) {
        const char *resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
        write(fd, resp, strlen(resp));
        close(fd);
        return;
    }

    fseek(f, 0, SEEK_END);
    long fileLength = ftell(f);
    fseek(f, 0, SEEK_SET);

    const char *mime = [self mimeTypeForPath:fullPath];

    // Construct HTTP response header with CORS enabled for localhost
    char headerBuf[512] = {0};
    snprintf(headerBuf, sizeof(headerBuf),
             "HTTP/1.1 200 OK\r\n"
             "Content-Type: %s\r\n"
             "Content-Length: %ld\r\n"
             "Access-Control-Allow-Origin: *\r\n"
             "Connection: close\r\n\r\n",
             mime, fileLength);

    write(fd, headerBuf, strlen(headerBuf));

    // Send file contents in 8KB chunks using plain write() (zero sendfile, 100% immune to SIGSYS)
    char fileBuf[8192];
    size_t n;
    while ((n = fread(fileBuf, 1, sizeof(fileBuf), f)) > 0) {
        ssize_t sent = write(fd, fileBuf, n);
        if (sent <= 0) break;
    }

    fclose(f);
    close(fd);
}

- (const char *)mimeTypeForPath:(NSString *)path {
    NSString *ext = [[path pathExtension] lowercaseString];
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return "text/html; charset=utf-8";
    if ([ext isEqualToString:@"js"]) return "application/javascript; charset=utf-8";
    if ([ext isEqualToString:@"css"]) return "text/css; charset=utf-8";
    if ([ext isEqualToString:@"json"]) return "application/json";
    if ([ext isEqualToString:@"png"]) return "image/png";
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return "image/jpeg";
    if ([ext isEqualToString:@"svg"]) return "image/svg+xml";
    if ([ext isEqualToString:@"woff2"]) return "font/woff2";
    if ([ext isEqualToString:@"woff"]) return "font/woff";
    if ([ext isEqualToString:@"ico"]) return "image/x-icon";
    return "application/octet-stream";
}

@end
