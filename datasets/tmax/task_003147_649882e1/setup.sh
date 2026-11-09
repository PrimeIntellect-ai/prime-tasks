#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc ffmpeg flac
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate intercepted command audio
    espeak -w /app/intercepted_command.wav "execute router restart semicolon script alert document dot cookie"

    # Create dummy vulnerable binary
    cat << 'EOF' > /tmp/router_mgr.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char *argv[]) {
    if(argc < 2) return 1;
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo %s", argv[1]);
    system(cmd);
    return 0;
}
EOF
    gcc /tmp/router_mgr.c -o /app/router_mgr.elf
    rm /tmp/router_mgr.c

    # Generate checksum
    sha256sum /app/router_mgr.elf > /app/checksums.txt

    # Create corpora
    cat << 'EOF' > /app/corpus/evil/logs.txt
execute router restart ; <script>alert(document.cookie)</script>
| curl -d @/proc/self/cmdline
EOF

    cat << 'EOF' > /app/corpus/clean/logs.txt
execute router restart
show interfaces
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
