#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/uptime_logs.txt
1700000000.000 1
1700000010.125 0
1700000015.250 1
1700000050.500 0
1700000055.750 1
1700000100.875 1
END
EOF

    cat << 'EOF' > /home/user/monitor.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *fp = fopen("/home/user/uptime_logs.txt", "r");
    if (!fp) return 1;

    float prev_time = 0.0;
    float total_uptime = 0.0;
    float total_time = 0.0;
    int prev_status = -1;

    float current_time;
    int current_status;

    while (!feof(fp)) {
        fscanf(fp, "%f %d", &current_time, &current_status);
        if (prev_status != -1) {
            float duration = current_time - prev_time;
            total_time += duration;
            if (prev_status == 1) {
                total_uptime += duration;
            }
        }
        prev_time = current_time;
        prev_status = current_status;
    }

    printf("Total Time: %.3f\n", total_time);
    printf("Uptime: %.3f\n", total_uptime);
    printf("Percentage: %.6f\n", (total_uptime / total_time) * 100.0);

    fclose(fp);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
