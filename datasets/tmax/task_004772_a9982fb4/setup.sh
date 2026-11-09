#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc expect logrotate
pip3 install pytest

mkdir -p /app
mkdir -p /home/user/logs

cat << 'EOF' > /app/sec_logger.c
#include <stdio.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        unsigned char b = (unsigned char)c;
        unsigned char out = (b ^ 0x5A) + 0x13;
        putchar(out);
    }
    return 0;
}
EOF

gcc -s -O2 /app/sec_logger.c -o /app/sec_logger
rm /app/sec_logger.c

cat << 'EOF' > /app/init_env.sh
#!/bin/bash
read -p "Username: " user
read -p "PIN: " pin
if [ "$user" == "sysadmin" ] && [ "$pin" == "8080" ]; then
    echo "AUTH_OK=1" > /home/user/logger.conf
else
    echo "AUTH_FAILED=1" > /home/user/logger.conf
fi
EOF
chmod +x /app/init_env.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
