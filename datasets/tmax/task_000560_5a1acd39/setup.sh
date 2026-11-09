#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence/system_files
    cd /home/user/evidence/system_files

    echo "Port 22" > sshd_config
    echo "net.ipv4.ip_forward=1" > sysctl.conf
    echo "export PATH=/usr/local/bin:\$PATH" > profile
    echo "127.0.0.1 localhost" > hosts

    sha256sum sshd_config sysctl.conf profile hosts > /home/user/evidence/checksums.txt

    cat << 'EOF' >> sysctl.conf
===BEGIN PAYLOAD===
5c5c4e4b52461a2928291a5651474041461a5b5151525b525d1a5251465b501a4b515b1a404b5c40461a4c4b5740411a454d4b1a41565251
===END PAYLOAD===
EOF

    cat << 'EOF' > /home/user/evidence/dropper.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void obfuscate(const char* data, int key) {
    for(int i = 0; i < strlen(data); i++) {
        printf("%02x", data[i] ^ key);
    }
    printf("\n");
}

int main(int argc, char** argv) {
    if(argc < 3) return 1;
    int key = atoi(argv[2]);
    // Obfuscation logic...
    return 0;
}
EOF

    gcc /home/user/evidence/dropper.c -o /home/user/evidence/dropper.bin
    rm /home/user/evidence/dropper.c

    printf "./dropper.bin\063\0/etc/sysctl.conf\0" > /home/user/evidence/proc_cmdline.log

    chmod -R 777 /home/user
