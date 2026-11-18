#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/release

    # 1. Create libauth.so with an undefined MD5_Init symbol
    cat << 'EOF' > /home/user/release/auth.c
void MD5_Init();
void do_auth() {
    MD5_Init();
}
EOF
    gcc -shared -fPIC -o /home/user/release/libauth.so /home/user/release/auth.c
    rm /home/user/release/auth.c

    # 2. Create handler.o
    cat << 'EOF' > /home/user/release/handler.s
.text
.global main
main:
    ret
.global check_auth
check_auth:
    mov $1, %eax
    ret
EOF
    as -o /home/user/release/handler.o /home/user/release/handler.s
    rm /home/user/release/handler.s

    # 3. Create thresholds.conf
    cat << 'EOF' > /home/user/release/thresholds.conf
timeout = 30 * 2
max_retries = (4 * 3) + 2 / 2
rate_limit = 1000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
