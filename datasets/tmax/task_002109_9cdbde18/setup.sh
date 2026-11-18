#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc docker.io docker-compose
    pip3 install pytest pexpect

    # Create directories
    mkdir -p /home/user/capacity-stack
    mkdir -p /home/user/backups
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create docker-compose.yml
    cat << 'EOF' > /home/user/capacity-stack/docker-compose.yml
version: '3'
services:
  log_aggregator:
    image: alpine
    command: sleep 3600
    networks:
      - front_tier
  db:
    image: alpine
    command: sleep 3600
    networks:
      - back_tier

networks:
  front_tier:
  back_tier:
EOF

    # Create interactive_backup.sh
    cat << 'EOF' > /app/interactive_backup.sh
#!/bin/bash
echo -n "Initiate backup? (y/n): "
read ans1
if [ "$ans1" != "y" ]; then echo "Aborted"; exit 1; fi
echo -n "Target volume: "
read ans2
if [ "$ans2" != "metrics_db" ]; then echo "Invalid volume"; exit 1; fi
echo -n "Max quota (GB): "
read ans3
if [ "$ans3" != "500" ]; then echo "Invalid quota"; exit 1; fi

echo "dummy backup content" > backup.tar.gz
echo "Backup successful."
EOF
    chmod +x /app/interactive_backup.sh

    # Create capacity_monitor C source and compile
    cat << 'EOF' > /app/capacity_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char buf[1024] = {0};
    fread(buf, 1, sizeof(buf)-1, f);
    fclose(f);

    int disk_used = 0;
    char *p = strstr(buf, "\"disk_used\":");
    if (p) disk_used = atoi(p + 12);

    if (disk_used < 0) {
        abort(); // crash on negative disk usage
    }

    char container[256] = {0};
    p = strstr(buf, "\"container\":");
    if (p) {
        char *start = strchr(p + 12, '"');
        if (start) {
            start++;
            char *end = strchr(start, '"');
            if (end) {
                int len = end - start;
                if (len < 255) strncpy(container, start, len);
            }
        }
    }

    if (strlen(container) > 0) {
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "echo %s > /dev/null", container);
        system(cmd); // unsafe system call
    }

    return 0;
}
EOF
    gcc -o /app/capacity_monitor /app/capacity_monitor.c
    strip /app/capacity_monitor
    rm /app/capacity_monitor.c

    # Generate corpora
    cat << 'EOF' > /tmp/gen_corpora.py
import json
import os
import random

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

for i in range(50):
    clean_data = {
        "disk_used": random.randint(10, 100),
        "disk_allocated": 200,
        "container": f"service_{i}"
    }
    with open(os.path.join(clean_dir, f"clean_{i}.json"), "w") as f:
        json.dump(clean_data, f)

for i in range(50):
    if i % 2 == 0:
        evil_data = {
            "disk_used": -random.randint(1, 100),
            "disk_allocated": 200,
            "container": f"service_{i}"
        }
    else:
        evil_data = {
            "disk_used": random.randint(10, 100),
            "disk_allocated": 200,
            "container": f"service_{i}; ls"
        }
    with open(os.path.join(evil_dir, f"evil_{i}.json"), "w") as f:
        json.dump(evil_data, f)
EOF
    python3 /tmp/gen_corpora.py
    rm /tmp/gen_corpora.py

    # Create user
    useradd -m -s /bin/bash user || true
    usermod -aG docker user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 755 /app
