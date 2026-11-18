#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc coreutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/clean_1.txt
useradd jdoe
ip route add 192.168.1.0/24 via 10.0.0.1
EOF

    cat << 'EOF' > /app/corpus/clean/clean_2.txt
ip route add 10.10.10.0/24 via 192.168.100.1
EOF

    cat << 'EOF' > /app/corpus/evil/evil_1.txt
ip route add 192.168.2.0/24 via 10.99.99.99
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.txt
useradd admin; cat /etc/passwd
EOF

    cat << 'EOF' > /app/corpus/evil/evil_3.txt
rm -rf /
EOF

    cat << 'EOF' > /app/corpus/evil/evil_4.txt
useradd admin-user!
EOF

    cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    char *file = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) {
            file = argv[i+1];
        }
    }
    char cmd[1024];
    if (file) {
        snprintf(cmd, sizeof(cmd), "cat %s | base64 -d | tr 'a-zA-Z' 'n-za-mN-ZA-M'", file);
    } else {
        snprintf(cmd, sizeof(cmd), "cat | base64 -d | tr 'a-zA-Z' 'n-za-mN-ZA-M'");
    }
    return system(cmd);
}
EOF

    gcc -O2 -s -o /app/config_decoder /tmp/decoder.c
    rm /tmp/decoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
