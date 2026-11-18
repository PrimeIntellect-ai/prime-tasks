#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/traffic_analyzer.c
#include <stdio.h>
#include <string.h>
int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    const char* token = argv[1];
    const char* payload = argv[2];
    if (strlen(token) != 10) return 2;
    if (strncmp(token, "NET_", 4) != 0) return 3;
    int sum = 0;
    for (int i = 4; i < 10; i++) sum += token[i];
    if (sum != 500) return 4;
    if (strcmp(payload, "admin' OR 1=1 --") == 0) return 42;
    return 5;
}
EOF
    gcc /tmp/traffic_analyzer.c -o /home/user/traffic_analyzer -O0
    rm /tmp/traffic_analyzer.c

    chmod -R 777 /home/user
