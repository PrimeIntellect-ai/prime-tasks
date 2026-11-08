#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
mkdir -p /opt
mkdir -p /var/log

cat << 'EOF' > /opt/wordlist.txt
apple
password123
hunter2
admin123
secret
qwerty
letmein1
supersecure
EOF

cat << 'EOF' > /tmp/token_gen.c
#include <stdio.h>
#include <string.h>

void to_hex(unsigned char* data, int len) {
    for(int i=0; i<len; i++) {
        printf("%02x", data[i]);
    }
    printf("\n");
}

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s:%s_S4LT", argv[1], argv[2]);

    // Custom simple hash algorithm instead of linking openssl just to keep it standalone
    unsigned char hash[16] = {0};
    for(int i=0; i<strlen(buffer); i++) {
        hash[i % 16] ^= buffer[i];
        hash[(i+1) % 16] += buffer[i];
    }

    to_hex(hash, 16);
    return 0;
}
EOF

gcc -O2 /tmp/token_gen.c -o /app/legacy_token_gen
strip /app/legacy_token_gen
chmod +x /app/legacy_token_gen
rm /tmp/token_gen.c

cat << 'EOF' > /var/log/auth_sys.log
[INFO] 10:00 - Failed login for user root (hash: 5f4dcc3b5aa765d61d8327deb882cf99)
[INFO] 10:05 - SUCCESSFUL login for user admin (hash: 2ab96390c7dbe3439de74d0c9b0b1767)
[INFO] 10:15 - Failed login for user db_user (hash: d8578edf8458ce06fbc5bb76a58c5ca4)
[INFO] 10:20 - SUCCESSFUL login for user db_user (hash: 5ebe2294ecd0e0f08eab7690d2a6ee69)
[INFO] 10:25 - SUCCESSFUL login for user backup_svc (hash: 1f3870be274f6c49b3e31a0c6728957f)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
