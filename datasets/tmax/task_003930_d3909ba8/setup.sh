#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    qemu-system-x86 \
    git \
    rustc \
    cargo \
    systemd \
    systemd-sysv \
    dbus \
    gcc \
    binutils \
    libc6-dev

pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    int ram = atoi(argv[1]);
    int cpu = atoi(argv[2]);
    if (ram * cpu <= 8192) {
        printf("OK\n");
    } else {
        printf("REJECT\n");
    }
    return 0;
}
EOF

gcc -O2 /tmp/oracle.c -o /app/capacity_oracle
strip /app/capacity_oracle
chmod +x /app/capacity_oracle
rm /tmp/oracle.c

useradd -m -s /bin/bash user || true
# Attempt to enable linger, might fail in chroot without running dbus
loginctl enable-linger user || true

chmod -R 777 /home/user
