#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/voice_query.wav "Please find the shortest path where the start node is 452 and the end node is 8910."

    # Generate the interactions.csv dataset
    cat << 'EOF' > /app/generate_graph.py
import random
random.seed(42)
with open('/app/interactions.csv', 'w') as f:
    f.write("source_node,target_node,weight\n")
    # Guarantee a path between 452 and 8910
    path = [452, 1000, 2000, 8910]
    for i in range(len(path)-1):
        f.write(f"{path[i]},{path[i+1]},1.0\n")
    # Generate random edges
    for _ in range(100000):
        u = random.randint(1, 10000)
        v = random.randint(1, 10000)
        if u != v:
            w = round(random.uniform(0.1, 10.0), 2)
            f.write(f"{u},{v},{w}\n")
EOF
    python3 /app/generate_graph.py
    rm /app/generate_graph.py

    # Create the naive C program
    cat << 'EOF' > /app/naive_query.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 3) return 1;
    printf("Naive query running... this would read the file repeatedly.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
