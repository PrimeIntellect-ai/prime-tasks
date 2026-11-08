#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev logrotate locales tzdata
    pip3 install pytest

    locale-gen ja_JP.UTF-8

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/daemon.c
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <locale.h>

int main() {
    // BUG: Missing timezone and locale initialization

    char buffer[256];
    time_t now;
    struct tm *local_info;

    for(int i=0; i<5; i++) {
        time(&now);
        local_info = localtime(&now);
        strftime(buffer, sizeof(buffer), "%c", local_info);
        printf("[%s] Heartbeat event\n", buffer);
        fflush(stdout);
        sleep(1);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
