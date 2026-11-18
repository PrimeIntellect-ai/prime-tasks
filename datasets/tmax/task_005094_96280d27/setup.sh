#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx binutils curl
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/libcalc.c
int sys_asm_calc_expr_v2(int a, int b) {
    return (a + b) * 3;
}
EOF

    gcc -shared -o /home/user/project/libcalc.so -fPIC /home/user/project/libcalc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
