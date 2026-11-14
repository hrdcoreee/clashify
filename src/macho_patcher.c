/*
 * macho_patcher.c - Lightweight C patcher to fix Mach-O platform on iOS
 *
 * Converts Go darwin-arm64 binaries (platform=1 / macOS) into iOS binaries (platform=2)
 * so that Apple dyld on iOS does not reject them with:
 *   "Reason: mach-o, but not built for platform macOS"
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>

#define MH_MAGIC_64 0xfeedfacf
#define LC_LOAD_DYLIB 0x0c
#define LC_BUILD_VERSION 0x32

#define PLATFORM_MACOS 1
#define PLATFORM_IOS 2
#define MIN_IOS_14 0x000e0000

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <path_to_mach_o_binary>\n", argv[0]);
        return 1;
    }

    const char *path = argv[1];
    int fd = open(path, O_RDWR);
    if (fd < 0) {
        perror("open failed");
        return 1;
    }

    uint32_t magic;
    if (read(fd, &magic, sizeof(magic)) != sizeof(magic)) {
        perror("read magic failed");
        close(fd);
        return 1;
    }

    if (magic != MH_MAGIC_64) {
        fprintf(stderr, "[-] Not a 64-bit Mach-O binary (magic: 0x%08x)\n", magic);
        close(fd);
        return 1;
    }

    // Read ncmds and sizeofcmds at offset 16
    uint32_t ncmds = 0, sizeofcmds = 0;
    lseek(fd, 16, SEEK_SET);
    read(fd, &ncmds, sizeof(ncmds));
    read(fd, &sizeofcmds, sizeof(sizeofcmds));

    off_t offset = 32;
    int patched_platform = 0;
    int patched_dylibs = 0;

    for (uint32_t i = 0; i < ncmds; i++) {
        uint32_t cmd = 0, cmdsize = 0;
        lseek(fd, offset, SEEK_SET);
        if (read(fd, &cmd, sizeof(cmd)) != sizeof(cmd) ||
            read(fd, &cmdsize, sizeof(cmdsize)) != sizeof(cmdsize)) {
            break;
        }

        if (cmd == LC_BUILD_VERSION) {
            uint32_t platform = 0;
            lseek(fd, offset + 8, SEEK_SET);
            read(fd, &platform, sizeof(platform));
            if (platform == PLATFORM_MACOS) {
                uint32_t new_platform = PLATFORM_IOS;
                uint32_t minos = MIN_IOS_14;
                uint32_t sdk = MIN_IOS_14;
                lseek(fd, offset + 8, SEEK_SET);
                write(fd, &new_platform, sizeof(new_platform));
                write(fd, &minos, sizeof(minos));
                write(fd, &sdk, sizeof(sdk));
                patched_platform = 1;
                printf("[+] Patched LC_BUILD_VERSION: platform macOS (1) -> iOS (2), minos 14.0\n");
            }
        } else if (cmd == LC_LOAD_DYLIB) {
            uint32_t stroff = 0;
            lseek(fd, offset + 8, SEEK_SET);
            read(fd, &stroff, sizeof(stroff));
            if (stroff > 0 && stroff < cmdsize) {
                size_t str_len = cmdsize - stroff;
                char *buf = malloc(str_len + 1);
                if (buf) {
                    lseek(fd, offset + stroff, SEEK_SET);
                    read(fd, buf, str_len);
                    buf[str_len] = '\0';
                    char *sub = strstr(buf, "/Versions/A/");
                    if (sub) {
                        char new_str[512] = {0};
                        size_t prefix_len = sub - buf;
                        memcpy(new_str, buf, prefix_len);
                        strcat(new_str, "/");
                        strcat(new_str, sub + 12); // skip "/Versions/A/"
                        memset(buf, 0, str_len);
                        memcpy(buf, new_str, strlen(new_str));
                        lseek(fd, offset + stroff, SEEK_SET);
                        write(fd, buf, str_len);
                        printf("[+] Normalized dylib path: %s\n", new_str);
                        patched_dylibs++;
                    }
                    free(buf);
                }
            }
        }

        offset += cmdsize;
    }

    close(fd);
    printf("[+] Done: patched_platform=%d, patched_dylibs=%d\n", patched_platform, patched_dylibs);
    return 0;
}
