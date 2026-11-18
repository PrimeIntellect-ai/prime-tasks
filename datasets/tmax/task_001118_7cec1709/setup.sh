#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cd /home/user

# Create attacker_bin.c
cat << 'EOF' > /home/user/attacker_bin.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_key() {
    printf("KEY: 0x4F\n");
    exit(0);
}

void process_input() {
    char buffer[64];
    // Vulnerable function
    gets(buffer);
}

int main() {
    process_input();
    return 0;
}
EOF

# Compile vulnerable binary
gcc -fno-stack-protector -z execstack -no-pie -o /home/user/attacker_bin /home/user/attacker_bin.c
rm /home/user/attacker_bin.c

# Create exfil.log
cat << 'EOF' > /home/user/exfil.log
GET /index.html HTTP/1.1
Host: compromised.local
Cookie: session_id=abc123z; auth_token=09030e0834273b3b3f10;
User-Agent: Mozilla/5.0

POST /api/data HTTP/1.1
Host: compromised.local
Cookie: auth_token=2c7f7f247e7c10377f3d1022;
Content-Length: 0

GET /images/logo.png HTTP/1.1
Host: compromised.local
Cookie: auth_token=7b3c3b7c3d1076767d7e32; tz=UTC;
EOF

chmod -R 777 /home/user
