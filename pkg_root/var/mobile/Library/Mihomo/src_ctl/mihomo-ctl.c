/*
 * mihomo-ctl.c - SUID Privileged Helper & Control Wrapper for Mihomo on iOS 14
 *
 * Runs with SUID root (chmod 4755) so that mobile user or iOS apps
 * can force start or stop Mihomo without permissions errors.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

static void do_start(void) {
    setuid(0);
    setgid(0);
    printf("[*] Starting Mihomo directly in background...\n");
    system("nohup /usr/local/bin/mihomo -d /var/mobile/Library/Mihomo > /var/mobile/Library/Mihomo/mihomo.log 2>&1 &");
}

static void do_stop(void) {
    setuid(0);
    setgid(0);
    printf("[*] Force stopping Mihomo (killall -9)...\n");
    system("killall -9 mihomo 2>/dev/null");
}

static void do_restart(void) {
    do_stop();
    sleep(1);
    do_start();
}

static void do_status(void) {
    system("/usr/local/bin/mihomo-ctl status");
}

int main(int argc, char *argv[]) {
    setuid(0);
    setgid(0);

    if (argc < 2) {
        printf("Usage: %s {start|stop|restart|status}\n", argv[0]);
        return 1;
    }

    const char *cmd = argv[1];
    if (strcmp(cmd, "start") == 0) {
        do_start();
    } else if (strcmp(cmd, "stop") == 0) {
        do_stop();
    } else if (strcmp(cmd, "restart") == 0) {
        do_restart();
    } else if (strcmp(cmd, "status") == 0) {
        do_status();
    } else {
        printf("Unknown command: %s\n", cmd);
        return 1;
    }

    return 0;
}
