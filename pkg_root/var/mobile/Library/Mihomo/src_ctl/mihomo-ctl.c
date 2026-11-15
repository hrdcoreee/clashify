/*
 * mihomo-ctl.c - SUID Privileged Helper & True Daemonizer for Mihomo on iOS 14
 *
 * Runs with SUID root (chmod 4755) so that iOS apps and non-root users
 * can launch Mihomo as a persistent, fully detached daemon that survives
 * app termination / closure. No launchctl required.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

static int is_running(void) {
    if (system("killall -0 mihomo >/dev/null 2>&1") == 0) {
        return 1;
    }
    if (system("pgrep -x mihomo >/dev/null 2>&1") == 0) {
        return 1;
    }
    return (system("ps aux 2>/dev/null | grep -E '(/usr/local/bin/mihomo|/mihomo -d)' | grep -v -E '(grep|mihomo-ctl|mihomo-suid|Mihomo\\.app)' | grep -q '.'") == 0);
}

static int daemonize_core(void) {
    if (is_running()) {
        printf("[!] Mihomo is already running.\n");
        return 0;
    }

    // 1. First fork
    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return -1;
    }
    if (pid > 0) {
        // Parent waits briefly, then exits 0 to caller
        usleep(500000); // 0.5s
        return 0;
    }

    // --- First Child ---
    // 2. Decouple from parent session & process group
    setsid();

    // 3. Ignore terminal signals
    signal(SIGHUP, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    // 4. Second fork: guarantees process can NEVER reacquire a controlling terminal
    pid = fork();
    if (pid < 0) {
        _exit(1);
    }
    if (pid > 0) {
        // First child terminates immediately
        _exit(0);
    }

    // --- Grandchild (True Daemon, reparented to PID 1) ---
    // 5. Elevate to root
    setuid(0);
    setgid(0);

    // 6. Setup directories
    mkdir("/var/mobile/Library/Mihomo", 0755);
    chdir("/var/mobile/Library/Mihomo");

    // 7. Redirect stdin to /dev/null, stdout/stderr to log file
    close(0);
    close(1);
    close(2);

    int devnull = open("/dev/null", O_RDONLY);
    if (devnull != 0) {
        dup2(devnull, 0);
        if (devnull > 0) close(devnull);
    }

    int logfd = open("/var/mobile/Library/Mihomo/mihomo.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (logfd >= 0) {
        dup2(logfd, 1);
        dup2(logfd, 2);
        if (logfd > 2) close(logfd);
    }

    // 8. Execute Mihomo core directly
    char *const argv[] = {
        "/usr/local/bin/mihomo",
        "-d",
        "/var/mobile/Library/Mihomo",
        NULL
    };
    char *const envp[] = {
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "HOME=/var/mobile",
        NULL
    };

    execve("/usr/local/bin/mihomo", argv, envp);
    _exit(1);
}

static void do_stop(void) {
    setuid(0);
    setgid(0);
    system("killall -9 mihomo 2>/dev/null || true");
    usleep(300000);
    if (is_running()) {
        system("killall -9 mihomo 2>/dev/null || true");
    }
}

int main(int argc, char *argv[]) {
    setuid(0);
    setgid(0);

    if (argc < 2) {
        printf("Usage: %s {start|stop|restart|status|daemon}\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "start") == 0 || strcmp(argv[1], "daemon") == 0) {
        return daemonize_core();
    } else if (strcmp(argv[1], "stop") == 0) {
        do_stop();
        return 0;
    } else if (strcmp(argv[1], "restart") == 0) {
        do_stop();
        usleep(500000);
        return daemonize_core();
    } else if (strcmp(argv[1], "status") == 0) {
        if (is_running()) {
            printf("RUNNING\n");
            return 0;
        } else {
            printf("STOPPED\n");
            return 1;
        }
    }

    // Fallback: execute arbitrary command as root
    char fullCmd[4096] = {0};
    for (int i = 1; i < argc; i++) {
        strncat(fullCmd, argv[i], sizeof(fullCmd) - strlen(fullCmd) - 2);
        if (i < argc - 1) {
            strncat(fullCmd, " ", sizeof(fullCmd) - strlen(fullCmd) - 1);
        }
    }
    return system(fullCmd);
}
