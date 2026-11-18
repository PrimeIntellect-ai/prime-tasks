#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/cloud_fstab
# Cloud Storage Volumes
vol_app_data 45
vol_db_main 150

vol_backups 20
vol_analytics 105
EOF

    cat << 'EOF' > /home/user/finops_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *f = fopen("/home/user/cloud_fstab", "r");
    if (!f) return 1;

    FILE *out = fopen("/home/user/cost_alerts.log", "a");
    if (!out) {
        fclose(f);
        return 1;
    }

    char line[256];
    while(fgets(line, sizeof(line), f)) {
        // Buggy tokenization: does not handle blank lines or check NULLs safely
        char *vol = strtok(line, " \n");
        if (vol[0] == '#') continue; // crashes if vol is NULL (e.g. blank line)

        char *cost_str = strtok(NULL, " \n");
        if (cost_str == NULL) continue;

        int cost = atoi(cost_str);
        if (cost > 100) {
            fprintf(out, "ALERT: volume %s exceeds 100\n", vol);
        }
    }

    fclose(f);
    fclose(out);
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
