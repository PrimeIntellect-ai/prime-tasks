#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl binutils gcc
pip3 install pytest

mkdir -p /home/user
echo -n "super_secret_master_key_2024" > /home/user/master.key

cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
int main() {
    printf("I am the agent.\n");
    return 0;
}
EOF
gcc /tmp/dummy.c -o /home/user/base_agent
echo "dummy_data" > /tmp/dummy_sec.bin
objcopy --add-section .secret_auth=/tmp/dummy_sec.bin --set-section-flags .secret_auth=contents,alloc,load,readonly /home/user/base_agent

chmod 755 /home/user/base_agent

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
