#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/app/data
cd /home/user/app

cat << 'EOF' > legacy.csv
user_id,filepath
101,data/avatar1.txt
102,data/avatar2.txt
103,data/avatar3.txt
EOF

echo -n "profile_pic_a" > data/avatar1.txt
echo -n "generic_user_b" > data/avatar2.txt
echo -n "custom_img_c" > data/avatar3.txt

cat << 'EOF' > hasher.c
#include <stdio.h>
int main() {
    printf("WEB_");
    int c;
    while ((c = getchar()) != EOF) putchar(c);
    return 0;
}
EOF

cat << 'EOF' > checksum.py
import sys

def calculate_hash(data: bytes) -> int:
    # Custom error-correcting checksum logic
    # Take the first 8 bytes, sum their ASCII/byte values, modulo 255
    chunk = data[:8]
    total = sum(chunk)
    return total % 255

if __name__ == '__main__':
    with open(sys.argv[1], 'rb') as f:
        data = f.read()
        print(calculate_hash(data))
EOF

chmod +x checksum.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
