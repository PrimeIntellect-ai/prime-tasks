#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential gdb strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_monitor
    cd /home/user/uptime_monitor

    git init
    git config user.name "SRE Admin"
    git config user.email "admin@sre.local"

    cat << 'EOF' > secret.txt
AUTH_TOKEN=sre_token_99x21
EOF

    cat << 'EOF' > Makefile
monitor: monitor.c
	gcc -O0 -g monitor.c -o monitor
EOF

    cat << 'EOF' > monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void simulate_monitoring() {
    float uptime_seconds = 16777210.0f; // roughly 194 days
    float target_uptime = 16777220.0f;

    // BUG: float precision loss at 16,777,216 means 16777216.0 + 1.0 = 16777216.0. Infinite loop!
    while (uptime_seconds < target_uptime) {
        uptime_seconds += 1.0f;
        // system call to make strace show the hang
        access("/tmp/monitor_heartbeat", F_OK);
    }
    printf("Uptime target reached.\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <auth_token>\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "sre_token_99x21") != 0) {
        fprintf(stderr, "Invalid auth token\n");
        return 1;
    }
    simulate_monitoring();
    printf("SLA Status: 99.999%% OK\n");
    return 0;
}
EOF

    git add secret.txt Makefile monitor.c
    git commit -m "Initial commit with monitoring script and secrets"

    git rm secret.txt
    git commit -m "Remove exposed secret token"

    chmod -R 777 /home/user
