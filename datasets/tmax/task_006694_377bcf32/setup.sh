#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/dummy.c
#include <stdio.h>
const char* secret_cookie = "SEC_COOKIE_aB3dE9fG1hJ4kL7m";
int main() {
    printf("Starting auth server...\n");
    return 0;
}
EOF

gcc /home/user/dummy.c -o /home/user/target_auth.elf
rm /home/user/dummy.c

cat << 'EOF' > /home/user/waf_rules.txt
# Blocked User-Agents
Block: User-Agent: .*curl.*
Block: User-Agent: .*wget.*
Block: User-Agent: .*python-requests.*

# Blocked Open Redirect Schemes
Block: GET /login\?.*next=http://.*
Block: GET /login\?.*next=https://.*
EOF

chmod -R 777 /home/user
