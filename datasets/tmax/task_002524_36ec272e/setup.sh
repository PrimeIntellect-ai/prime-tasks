#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl openssl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/qemu_probe.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char* token = getenv("PROBE_TOKEN");
    if (!token || strcmp(token, "sre_uptime_55") != 0) {
        fprintf(stderr, "Invalid or missing PROBE_TOKEN\n");
        return 1;
    }
    if (argc != 3 || strcmp(argv[1], "--state-file") != 0) {
        fprintf(stderr, "Usage: %s --state-file <path>\n", argv[0]);
        return 1;
    }
    struct stat st;
    if (stat(argv[2], &st) != 0) {
        fprintf(stderr, "Cannot stat file\n");
        return 1;
    }
    if ((st.st_mode & 0777) != 0400) {
        fprintf(stderr, "Insecure permissions on state file. Must be 0400.\n");
        return 1;
    }
    printf("{\"status\": \"UP\", \"target\": \"QEMU_VNC\", \"latency\": \"15ms\"}\n");
    return 0;
}
EOF
    gcc -s -o /app/qemu_probe /tmp/qemu_probe.c
    rm /tmp/qemu_probe.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
