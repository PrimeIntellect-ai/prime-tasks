#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/mailer_daemon.c
#include <stdio.h>
int main() {
    printf("Mailer Daemon v2.0 ready.\n");
    return 0;
}
EOF

    chmod -R 777 /home/user
