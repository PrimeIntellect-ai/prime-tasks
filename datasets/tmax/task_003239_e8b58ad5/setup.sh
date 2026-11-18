#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/auth_service.c
#include <stdio.h>
int main() {
    const char* salt = "N3tw0rk_S3cr3t_99!";
    return 0;
}
EOF
gcc -o /app/auth_service /tmp/auth_service.c
strip /app/auth_service
rm /tmp/auth_service.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
