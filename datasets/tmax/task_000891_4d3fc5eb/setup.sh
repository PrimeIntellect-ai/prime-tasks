#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils curl gawk
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/health_signer.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 3) { return 1; }
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo -n '%s_SECRET-SRE-KEY_%s' | md5sum | awk '{print $1}'", argv[1], argv[2]);
    system(cmd);
    return 0;
}
EOF
    gcc -O2 /tmp/health_signer.c -o /app/health_signer
    strip /app/health_signer
    rm /tmp/health_signer.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_health.log
[2023-10-12T09:55:00Z] NODE=app-1 IP=10.0.0.5 STATUS=ONLINE RESPONSE_TIME=45ms
[2023-10-12T10:00:00Z] NODE=app-2 IP=10.0.0.6 STATUS=OFFLINE RESPONSE_TIME=TIMEOUT
[2023-10-12T10:05:00Z] NODE=db-1 IP=192.168.1.50 STATUS=ONLINE RESPONSE_TIME=12ms
[2023-10-12T10:10:00Z] NODE=cache-1 IP=172.16.0.4 STATUS=OFFLINE RESPONSE_TIME=TIMEOUT
[2023-10-12T10:15:00Z] NODE=app-1 IP=10.0.0.5 STATUS=ONLINE RESPONSE_TIME=48ms
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
