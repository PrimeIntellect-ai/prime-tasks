#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils ltrace strace curl openssl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    long disk_used = atol(argv[1]);
    long disk_total = atol(argv[2]);
    long ram_used = atol(argv[3]);
    long cpu_load = atol(argv[4]);

    long disk_ratio = (disk_used * 100) / disk_total; // integer division
    long score = (disk_ratio * 2) + (ram_used / 100) + (cpu_load * 3);

    const char* status = "OK";
    if (score > 500) {
        status = "CRIT";
    } else if (score > 300) {
        status = "WARN";
    }

    printf("STATUS: %s - Score: %ld\n", status, score);
    return 0;
}
EOF
    gcc -O2 -s -o /app/legacy_health_checker /app/oracle.c
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
