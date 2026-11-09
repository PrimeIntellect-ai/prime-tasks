#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip valgrind gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/bin /home/user/src

    cat << 'EOF' > /home/user/api_topology.txt
ConfigService -> 
DatabaseService -> ConfigService
CacheService -> DatabaseService
AuthService -> CacheService
GatewayService -> AuthService
EOF

    cat << 'EOF' > /home/user/src/auth_service.c
#include <stdlib.h>
#include <stdio.h>

int main() {
    // Simulate an API initialization
    printf("Starting AuthService...\n");

    // Simulate a memory leak of exactly 4096 bytes
    void *leaked_memory = malloc(4096);

    printf("AuthService shutting down...\n");
    return 0;
}
EOF

    gcc -g /home/user/src/auth_service.c -o /home/user/bin/auth_service

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
