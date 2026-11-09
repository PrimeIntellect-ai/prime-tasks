#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/abi_task
    cd /home/user/abi_task

    cat << 'EOF' > old.c
int core_process(int a) { return a + 1; }
int legacy_hash_func(int a, int b) { return a * b; }
int matrix_transform_v1(int x) { return x ^ 0x42; }
int validate_state() { return 1; }
EOF

    cat << 'EOF' > new.c
int core_process(int a) { return a + 2; }
int matrix_transform_v2(int x) { return x ^ 0x99; }
int validate_state() { return 1; }
int optimize_path() { return 0; }
EOF

    gcc -shared -fPIC old.c -o libold.so
    gcc -shared -fPIC new.c -o libnew.so

    rm old.c new.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
