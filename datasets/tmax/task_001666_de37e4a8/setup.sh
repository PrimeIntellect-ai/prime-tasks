#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        redis-server

    pip3 install pytest flask fastapi uvicorn redis requests

    mkdir -p /home/user/app/backend

    cat << 'EOF' > /home/user/app/backend/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    int v;
    fscanf(f, "%d", &v);
    // Fake parsing edges...
    int a, b;
    while(fscanf(f, "%d %d", &a, &b) == 2) {}
    fclose(f);

    usleep(100000); // 100ms artificial delay to force caching requirement

    for(int i=0; i<v; i++) {
        double angle = 2.0 * M_PI * i / v;
        printf("%.3f,%.3f\n", cos(angle), sin(angle));
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/backend/Makefile
layout_engine: main.c
	gcc -o layout_engine main.c
EOF

    cat << 'EOF' > /home/user/evaluate.py
import requests
import time
import sys

payload = {
    "vertices": 3,
    "edges": [[0, 1], [1, 2], [2, 0]]
}

# Wait for API to be up
for _ in range(20):
    try:
        requests.post("http://127.0.0.1:8000/api/layout", json=payload, timeout=2)
        break
    except:
        time.sleep(0.5)
else:
    print("API not reachable")
    sys.exit(1)

# Correctness check
resp = requests.post("http://127.0.0.1:8000/api/layout", json=payload).json()
if "coordinates" not in resp or len(resp["coordinates"]) != 3:
    print("Incorrect JSON format")
    sys.exit(1)

# Metric evaluation (Latency)
start = time.time()
for _ in range(100):
    requests.post("http://127.0.0.1:8000/api/layout", json=payload)
total_time = time.time() - start

print(f"METRIC: {total_time}")
if total_time > 0.5:
    sys.exit(1)
sys.exit(0)
EOF

    useradd -m -s /bin/bash user || true

    # Ensure redis is started when bash is invoked for testing
    echo "redis-server --daemonize yes" >> /home/user/.bashrc

    chmod -R 777 /home/user
