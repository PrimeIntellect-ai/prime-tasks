#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data
    mkdir -p /app

    # Generate the network_logs.csv
    cat << 'EOF' > /tmp/gen_data.py
import random

with open("/home/user/data/network_logs.csv", "w") as f:
    f.write("timestamp,source_node,target_node,operation_type,payload_size,status\n")
    f.write("1,A100,N1,DATA_TRANSFER,100,SUCCESS\n")
    f.write("2,N1,N2,DATA_TRANSFER,100,SUCCESS\n")
    f.write("3,N2,Z999,DATA_TRANSFER,100,SUCCESS\n")

    nodes = [f"X{i}" for i in range(1000)]
    for i in range(500000):
        src = random.choice(nodes)
        tgt = random.choice(nodes)
        op = random.choice(["DATA_TRANSFER", "PING", "AUTH"])
        status = random.choice(["SUCCESS", "FAILED"])
        size = random.randint(10, 1000)
        f.write(f"{i+4},{src},{tgt},{op},{size},{status}\n")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create the slow reference binary
    cat << 'EOF' > /app/path_finder.c
#include <stdio.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    // Artificial delay to simulate poor performance
    sleep(2);
    printf("{\"source\": \"A100\", \"target\": \"Z999\", \"hops\": 3, \"bottleneck_capacity\": 100, \"path\": [\"A100\", \"N1\", \"N2\", \"Z999\"]}\n");
    return 0;
}
EOF
    gcc /app/path_finder.c -o /app/path_finder
    rm /app/path_finder.c

    chmod -R 777 /home/user
    chmod -R 777 /app
