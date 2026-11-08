#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y gcc nginx websockify gdb strace binutils sudo curl

    # Create the fixture directory and compile the stripped binary
    mkdir -p /app
    cat << 'EOF' > /tmp/setup_waf_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char *mode = getenv("WAF_MODE");
    if (!mode || strcmp(mode, "strict") != 0) {
        fprintf(stderr, "FATAL: Invalid mode\n");
        return 1;
    }
    if (argc < 2 || strcmp(argv[1], "--filter") != 0) {
        fprintf(stderr, "FATAL: Invalid args\n");
        return 1;
    }

    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        printf("[WAF-SECURE] %s", buffer);
        fflush(stdout);
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/setup_waf_engine.c -o /app/waf_engine
    rm /tmp/setup_waf_engine.c

    # Create user and setup sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user
    chmod 0440 /etc/sudoers.d/user

    chmod -R 777 /home/user
