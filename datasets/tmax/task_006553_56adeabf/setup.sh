#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang
    pip3 install pytest

    mkdir -p /home/user/release
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/release/Makefile
logparser: logparser.c
	gcc -O2 logparser.c -o logparser
EOF

    cat << 'EOF' > /home/user/release/logparser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    FILE *in = fopen(argv[1], "r");
    if (!in) return 1;

    // The bug: hardcoded temp file
    FILE *temp = fopen("/tmp/scratch.tmp", "w");
    if (!temp) return 1;

    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), in)) {
        fputs(buffer, temp);
    }
    fclose(in);
    fclose(temp);

    // Dummy math usage to justify -lm requirement
    double dummy = sin(1.0);

    temp = fopen("/tmp/scratch.tmp", "r");
    int error_count = 0;
    while (fgets(buffer, sizeof(buffer), temp)) {
        if (strstr(buffer, "ERROR") != NULL) {
            error_count++;
        }
    }
    fclose(temp);

    printf("%d\n", error_count + (int)(dummy*0.0));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/logs/app_01.txt
INFO: Starting
ERROR: Failed to bind
INFO: Retrying
EOF

    cat << 'EOF' > /home/user/logs/app_02.txt
INFO: OK
WARN: Slow
ERROR: Timeout
ERROR: Disk full
ERROR: Crash
EOF

    cat << 'EOF' > /home/user/logs/app_03.txt
INFO: Nothing to see here
EOF

    cat << 'EOF' > /home/user/logs/app_04.txt
ERROR: One
ERROR: Two
EOF

    cat << 'EOF' > /home/user/logs/app_05.txt
ERROR: A
ERROR: B
ERROR: C
ERROR: D
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/release
    chown -R user:user /home/user/logs
    chmod -R 777 /home/user
