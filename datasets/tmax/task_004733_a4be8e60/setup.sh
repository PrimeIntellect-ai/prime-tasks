#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/wordlist.txt
admin
password123
qwerty
letmein
supersecret
sunshine
dragon
EOF

cat << 'EOF' > /home/user/auth.c
#include <stdio.h>
int main() {
    const char* hash = "HASH:c8d8b15fa4d4bb8831006eb46cdb12b5cdbaad3d4f1076f7ce3e30252ad8d052";
    const char* salt = "SALT:salt123";
    printf("Auth service loaded.\n");
    return 0;
}
EOF
gcc -o /home/user/auth_binary /home/user/auth.c
rm /home/user/auth.c

cat << 'EOF' > /home/user/policy.conf
DENY ALL
ALLOW USER 1234
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
