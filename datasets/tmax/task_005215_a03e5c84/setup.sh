#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gdb binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/uptime_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void calculate_metrics(volatile float current_uptime) {
    volatile float next_uptime = current_uptime + 1.0f;
    volatile int delta = (int)(next_uptime - current_uptime);
    // Integer division by zero when current_uptime reaches 16777216.0 (2^24)
    // due to 32-bit float precision limits.
    volatile int metric = 100 / delta;
    (void)metric;
}

int main() {
    char *secret = malloc(64);
    strcpy(secret, "SRE_MONITOR_SECRET_992837465");

    // Fast forward to just before the precision loss boundary
    float uptime = 16777215.0f;
    calculate_metrics(uptime); // Succeeds, delta = 1

    uptime += 1.0f; // uptime becomes 16777216.0f
    calculate_metrics(uptime); // Crashes, delta = 0

    return 0;
}
EOF

gcc -O0 -o /home/user/uptime_monitor /tmp/uptime_monitor.c

cd /home/user
ulimit -c unlimited
./uptime_monitor || true

# Try to find and rename the core dump if it was generated
find . -maxdepth 1 -name "core*" -type f -exec mv {} core \; 2>/dev/null || true

# Fallback: use GDB to generate the core dump if ulimit/core_pattern didn't work in build env
if [ ! -f /home/user/core ]; then
    cat << 'EOF' > /tmp/gen_core.gdb
run
generate-core-file /home/user/core
quit
EOF
    gdb -batch -x /tmp/gen_core.gdb /home/user/uptime_monitor || true
fi

chmod -R 777 /home/user
