#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/emitter.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    long start_ts = 1700000000;
    int endpoints[3] = {0, 1, 2};
    const char* eps[] = {"/login", "/data", "/health"};

    // Generate 5000 log entries over ~50 minutes
    for(int i=0; i<5000; i++) {
        long ts = start_ts + (i * 0.6); // ~1 entry every 0.6 seconds
        int ip1 = 192, ip2 = 168, ip3 = 1;
        int ip4 = rand() % 255;

        int ep_idx = 1;
        int r = rand() % 100;
        if(r < 20) ep_idx = 0;
        else if(r < 30) ep_idx = 2;

        // Inject bad unicode randomly
        const char* ua = (rand() % 10 == 0) ? "Mozilla/5.0 \\uXX12 broken" : "Mozilla/5.0";

        printf("{\"timestamp\": %ld, \"client_ip\": \"%d.%d.%d.%d\", \"endpoint\": \"%s\", \"user_agent\": \"%s\"}\n",
               ts, ip1, ip2, ip3, ip4, eps[ep_idx], ua);
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/emitter.c -o /app/log_emitter
    rm /tmp/emitter.c
    chmod +x /app/log_emitter

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
