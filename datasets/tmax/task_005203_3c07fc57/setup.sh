#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sleuthkit e2tools e2fsprogs
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/parser.c
#include <stdio.h>
#include <stdlib.h>

void parse_log(const char *filename) {
    FILE *f = fopen(filename, "r");
    if (!f) return;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), f)) {
        char ip[16];
        char user[32];
        // The vulnerability: missing bounds checking in sscanf
        if (sscanf(buffer, "IP: %s USER: %s", ip, user) == 2) {
            printf("Parsed IP: %s\n", ip);
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        parse_log(argv[1]);
    }
    return 0;
}
EOF

    # Create the ext4 image and populate it without mounting
    dd if=/dev/zero of=/home/user/logs.img bs=1M count=10
    mkfs.ext4 /home/user/logs.img

    echo "IP: 192.168.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1.1 USER: admin" > /tmp/corrupt_record.log

    e2cp /tmp/corrupt_record.log /home/user/logs.img:/
    e2rm /home/user/logs.img:/corrupt_record.log

    rm /tmp/corrupt_record.log

    chmod -R 777 /home/user
