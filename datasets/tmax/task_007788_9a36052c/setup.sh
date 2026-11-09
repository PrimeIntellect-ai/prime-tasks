#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev git expect logrotate
pip3 install pytest

mkdir -p /home/user/src
cat << 'EOF' > /home/user/src/net_monitor.c
#include <stdio.h>
#include <time.h>

int main() {
    FILE *f = fopen("net_stats.log", "a");
    if (f == NULL) return 1;
    fprintf(f, "Network stats recorded at %ld\n", time(NULL));
    fclose(f);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
