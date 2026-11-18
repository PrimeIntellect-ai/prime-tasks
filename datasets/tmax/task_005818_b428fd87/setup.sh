#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils
    pip3 install pytest

    mkdir -p /home/user/configs

    # Create a simple C file to compile into different binaries
    cat << 'EOF' > /home/user/configs/dummy.c
#include <stdio.h>
void func() { printf("Hello"); }
int main() { func(); return 0; }
EOF

    # Compile to create slightly different ELF files (using different entry points / linker options)
    gcc /home/user/configs/dummy.c -o /home/user/configs/app_v1.elf -Wl,-e,func
    gcc /home/user/configs/dummy.c -o /home/user/configs/app_v2.elf -Wl,-e,main
    gcc /home/user/configs/dummy.c -o /home/user/configs/app_v3.elf 

    # Create JSON metadata
    echo '{"config_id": "cfg_init", "binary": "app_v3.elf", "timestamp": 1600000000}' > /home/user/configs/update1.json
    echo '{"config_id": "cfg_patch", "binary": "app_v1.elf", "timestamp": 1600000050}' > /home/user/configs/update2.json
    echo '{"config_id": "cfg_final", "binary": "app_v2.elf", "timestamp": 1600000100}' > /home/user/configs/update3.json

    rm /home/user/configs/dummy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
