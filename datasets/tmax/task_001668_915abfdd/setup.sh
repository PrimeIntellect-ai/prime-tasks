#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/uptime_analyzer.c
#define _XOPEN_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    setenv("TZ", "UTC", 1);
    tzset();

    char line[256];
    time_t last_time = 0;
    int is_up = 0;
    long total_uptime = 0;

    while (fgets(line, sizeof(line), f)) {
        struct tm tm;
        char status[10];

        if (strlen(line) < 20) continue;

        char time_str[20];
        strncpy(time_str, line, 19);
        time_str[19] = '\0';

        if (strptime(time_str, "%Y-%m-%d %H:%M:%S", &tm) == NULL) {
            continue;
        }

        if (sscanf(line + 20, "%9s", status) != 1) {
            continue;
        }

        time_t current_time = mktime(&tm);
        if (current_time == -1) continue;

        if (last_time != 0 && is_up) {
            total_uptime += (current_time - last_time);
        }

        if (strcmp(status, "UP") == 0) {
            is_up = 1;
        } else if (strcmp(status, "DOWN") == 0) {
            is_up = 0;
        } else {
            // Bug: Does not skip invalid statuses, causing last_time to update incorrectly.
        }

        last_time = current_time;
    }

    fclose(f);
    printf("Total uptime: %ld seconds\n", total_uptime);
    return 0;
}
EOF

cat << 'EOF' > /home/user/system.log
2023-11-05 00:00:00 UP
2023-11-05 01:15:00 DOWN
garbage garbage garbage
2023-11-05 01:45:00 UP
2023-11-05 04:00:00 DOWN
2023-11-05 04:30:00 INVALIDSTATUS
2023-11-05 05:00:00 UP
2023-11-05 06:00:00 DOWN
EOF

chmod -R 777 /home/user
