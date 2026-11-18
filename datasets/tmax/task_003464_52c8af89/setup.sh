#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git qemu-system-x86 qemu-utils curl netcat-openbsd
    pip3 install pytest

    mkdir -p /app

    # Create legacy_monitor source
    cat << 'EOF' > /tmp/legacy_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main() {
    char *tz = getenv("TZ");
    char *lc = getenv("LC_ALL");
    char *path = getenv("PATH");

    if (!tz || strcmp(tz, "America/New_York") != 0) {
        printf("ERR\n");
        return 1;
    }
    if (!lc || strcmp(lc, "C") != 0) {
        printf("ERR\n");
        return 1;
    }
    if (!path || !strstr(path, "/usr/local/sbin")) {
        printf("ERR\n");
        return 1;
    }

    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/legacy_qmp.sock", sizeof(addr.sun_path) - 1);
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        printf("ERR\n");
        return 1;
    }
    close(sock);

    printf("HEARTBEAT_OK_78291");
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_monitor.c -o /app/legacy_monitor
    strip /app/legacy_monitor
    rm /tmp/legacy_monitor.c

    # Create dummy qcow2 image
    qemu-img create -f qcow2 /app/legacy_vm.qcow2 1M

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
