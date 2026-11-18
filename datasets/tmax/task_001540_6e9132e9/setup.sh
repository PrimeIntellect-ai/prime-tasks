#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_project/src
    mkdir -p /home/user/uptime_project/legacy_headers
    mkdir -p /home/user/uptime_project/modern_headers

    cat << 'EOF' > /home/user/uptime_project/legacy_headers/config.h
#ifndef CONFIG_H
#define CONFIG_H
#define MAX_SERVERS 10
#endif
EOF

    cat << 'EOF' > /home/user/uptime_project/modern_headers/config.h
#ifndef CONFIG_H
#define CONFIG_H
#define MAX_SERVERS 1000
#endif
EOF

    cat << 'EOF' > /home/user/uptime_project/src/uptime_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include "config.h"

// calculate_sla should return (uptime / (total_time - maintenance_time)) * 100
// Bug: integer division results in 0 if uptime < (total_time - maintenance_time)
float calculate_sla(int uptime, int total_time, int maintenance_time) {
    if (total_time - maintenance_time <= 0) return 0.0;
    float sla = (uptime / (total_time - maintenance_time)) * 100;
    return sla;
}

int main(int argc, char *argv[]) {
    if (argc < 4) {
        printf("Usage: %s <uptime> <total> <maint>\n", argv[0]);
        return 1;
    }

    int uptime = atoi(argv[1]);
    int total = atoi(argv[2]);
    int maint = atoi(argv[3]);

    printf("%.2f\n", calculate_sla(uptime, total, maint));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/uptime_project/Makefile
CC=gcc
CFLAGS=-Wall -I./legacy_headers

uptime_monitor: src/uptime_monitor.c
	$(CC) $(CFLAGS) -o uptime_monitor src/uptime_monitor.c

clean:
	rm -f uptime_monitor
EOF

    echo -ne "\x00\x00\x11\x22\x33SLA_TARGET_HOST=srv-092.prod.internal\x00\x00\x99\xAA" > /home/user/uptime_project/memory.dmp

    chown -R user:user /home/user/uptime_project
    chmod -R 777 /home/user
