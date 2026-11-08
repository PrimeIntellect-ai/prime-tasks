#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go redis-server build-essential
    pip3 install pytest

    mkdir -p /app/legacy /app/service

    cat << 'EOF' > /app/legacy/telemetry.c
#include "telemetry.h"
#include <stddef.h>

long long process_telemetry(int* data, size_t len) {
    long long sum = 0;
    // BUG: <= len causes out of bounds read, triggering UB/segfaults on large inputs.
    for (size_t i = 0; i <= len; i++) {
        sum += data[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/legacy/telemetry.h
#ifndef TELEMETRY_H
#define TELEMETRY_H
#include <stddef.h>
long long process_telemetry(int* data, size_t len);
#endif
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
# Start redis
redis-server --daemonize yes --port 6379
# TODO: Build and start Go API
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
