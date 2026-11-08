#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils golang
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/log_obfuscator.c
#include <stdio.h>

int main() {
    int c;
    unsigned long long i = 0;
    while ((c = fgetc(stdin)) != EOF) {
        unsigned char b = (unsigned char)c;
        b = b ^ 0x5A;
        b = (unsigned char)((b + (i % 8)) & 0xFF);
        fputc(b, stdout);
        i++;
    }
    return 0;
}
EOF

gcc -O2 /tmp/log_obfuscator.c -o /app/log_obfuscator
strip -s /app/log_obfuscator
rm /tmp/log_obfuscator.c

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/compromised_sshd_config
Port 22
PermitRootLogin yes
PermitEmptyPasswords yes
Protocol 1
MACs hmac-md5,hmac-sha1
PasswordAuthentication yes
EOF

chmod -R 777 /home/user
