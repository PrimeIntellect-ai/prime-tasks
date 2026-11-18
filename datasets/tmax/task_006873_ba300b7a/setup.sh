#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/vm_service.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char *display = getenv("VNC_DISPLAY");
    // Intentional bug: no NULL check, crashes if VNC_DISPLAY is unset
    printf("Starting QEMU on VNC display %s\n", display);
    return 0;
}
EOF

    chmod -R 777 /home/user
