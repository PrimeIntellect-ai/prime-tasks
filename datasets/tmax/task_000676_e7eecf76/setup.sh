#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/suspicious.c
#include <stdio.h>
#include <string.h>
int main(int argc, char** argv) {
    if(argc > 1 && strcmp(argv[1], "B4ckd00r_T0k3n_9921") == 0) {
        printf("root\n");
    }
    return 0;
}
EOF
    gcc /tmp/suspicious.c -o /home/user/suspicious_net_helper
    rm /tmp/suspicious.c

    touch /home/user/old_backup_tool

    chmod -R 777 /home/user
    chmod 4755 /home/user/old_backup_tool
