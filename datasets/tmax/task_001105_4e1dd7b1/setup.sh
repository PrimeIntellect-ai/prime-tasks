#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
echo "2023-10-10T10:00:00 INFO 100 Started" >> /home/user/app_data/metrics.log
echo "2023-10-10T10:00:01 CRITICAL 400 Disk read error" >> /home/user/app_data/metrics.log
echo "2023-10-10T10:00:02 WARNING 50 High latency" >> /home/user/app_data/metrics.log
echo "2023-10-10T10:00:03 CRITICAL 120 Connection dropped" >> /home/user/app_data/metrics.log
echo "2023-10-10T10:00:04 INFO 200 Running" >> /home/user/app_data/metrics.log
sleep 10
EOF
    chmod +x /home/user/worker.sh

    cat << 'EOF' > /home/user/supervisor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main() {
    int max_quota = 0;
    FILE *f = fopen("/home/user/app_data/quota_config", "r");

    // BUG 1: No NULL check here, causing segfault if init_storage.sh isn't run first
    char line[256];
    fgets(line, sizeof(line), f);

    // BUG 2: Hardcoded value instead of parsing line
    max_quota = 1000;
    fclose(f);

    printf("Starting worker with quota %d\n", max_quota);
    system("/home/user/worker.sh");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
