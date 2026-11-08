#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_monitor

    cat << 'EOF' > /home/user/uptime_monitor/requests.log
2023-10-01T10:00:00 SUCCESS
2023-10-01T10:01:00 ERROR
2023-10-01T10:02:00 SUCCESS
2023-10-01T10:03:00 SUCCESS
2023-10-01T10:04:00 ERROR
EOF

    cat << 'EOF' > /home/user/uptime_monitor/monitor.c
#include <stdio.h>
#include <string.h>

int main() {
    // BUG 1: Opening the wrong file (query result debugging)
    FILE *fp = fopen("request.log", "r");
    if (!fp) {
        printf("Failed to open log\n");
        return 1;
    }

    int total = 0;
    int errors = 0;
    char line[256];

    while (fgets(line, sizeof(line), fp)) {
        total++;
        if (strstr(line, "ERROR") != NULL) {
            errors++;
        }
    }
    fclose(fp);

    // BUG 2: Formula implementation (Integer division will result in 0)
    float uptime = (total - errors) / total * 100.0;

    // BUG 3: Build failure (Typo in variable name)
    printf("Uptime: %.2f%%\n", uptim);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/uptime_monitor/Makefile
monitor: monitor.c
	gcc -o monitor monitor.c -Wall
EOF

    chmod -R 777 /home/user
