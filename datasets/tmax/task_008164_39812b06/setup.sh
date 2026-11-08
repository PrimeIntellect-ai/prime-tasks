#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gcc-aarch64-linux-gnu binutils binutils-aarch64-linux-gnu make
    pip3 install --default-timeout=100 pytest

    mkdir -p /home/user/build

    cat << 'EOF' > /home/user/build/auth_helper.c
#include <stdio.h>

void websec_verify_token() {
    // verify token logic
}

void websec_hash_pwd() {
    // hash password logic
}

void websec_debug_bypass() {
    // DANGER: test backdoor left in by a developer
}

int main() {
    websec_verify_token();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/build/Makefile
all: auth_x86 auth_arm

auth_x86: auth_helper.c
    gcc -o auth_x86 auth_helper.c

auth_arm: auth_helper.c
    aarch64-linux-gnu-gcc -o auth_arm auth_helper.c
EOF

    cat << 'EOF' > /home/user/build/expected_symbols.txt
websec_verify_token
websec_hash_pwd
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/build
    chmod -R 777 /home/user
