#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cargo rustc jq
    pip3 install pytest

    mkdir -p /home/user/legacy_tool
    mkdir -p /home/user/data
    mkdir -p /home/user/wrapper

    cat << 'EOF' > /home/user/data/input.txt
DATA_START
rec_1: OK
rec_2: ANOMALY
rec_3: OK
rec_4: OK
rec_5: ANOMALY
rec_6: OK
rec_7: OK
DATA_END
EOF

    cat << 'EOF' > /home/user/legacy_tool/fast-stat.c
#include <stdio.h>
/* BUG: missing <stdlib.h> and <string.h> */

int main() {
    FILE *fp;
    char path[] = "/var/log/legacy_telemetry.log"; /* BUG: hardcoded */
    char buffer[256];
    int records = 0;
    int anomalies = 0;
    int duration = 42; /* simulated constant */

    fp = fopen(path, "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return 1;
    }

    while (fgets(buffer, sizeof(buffer), fp)) {
        if (strstr(buffer, "rec_") != NULL) records++;
        if (strstr(buffer, "ANOMALY") != NULL) anomalies++;
    }

    fclose(fp);

    printf("--- STAT REPORT ---\n");
    printf("Records: %d\n", records);
    printf("Anomalies: %d\n", anomalies);
    printf("Duration: %d\n", duration);
    printf("--- END ---\n");

    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_tool/Makefile
all: fast-stat

fast-stat: fast-stat.c
    gcc -o fast-stat fast-stat.c -Wmissing-headers
# BUG: 4 spaces instead of a tab, and `-Wmissing-headers` is not a standard gcc flag (should be removed or changed).
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
