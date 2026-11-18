#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/process_math.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <coefficient>\n", argv[0]);
        return 1;
    }

    long long coeff = atoll(argv[1]);
    char line[256];

    while (fgets(line, sizeof(line), stdin)) {
        int tx;
        long long val;

        if (sscanf(line, "TX:%d VAL:%lld", &tx, &val) == 2) {
            // INTERMITTENT BUG: Crashes when value is a multiple of 17
            if (val % 17 == 0) {
                char *ptr = NULL;
                *ptr = 'x'; // Segmentation fault
            }

            long long result = val * coeff;
            printf("TX:%d RESULT:%lld\n", tx, result);
        }
    }
    return 0;
}
EOF

head -c 10000 /dev/urandom > /home/user/memdump.dat
echo -n "SECRET_COEFF=4291" >> /home/user/memdump.dat
head -c 5000 /dev/urandom >> /home/user/memdump.dat

python3 -c '
with open("/home/user/data.wal", "wb") as f:
    f.write(b"TX:1 VAL:10\nTX:2 VAL:25\nTX:3 VAL:12\n")
    f.write(b"\x00\xFF\xFA\x88GarbageLine\n")
    f.write(b"TX:4 VAL:34\nTX:5 VAL:8\n")
    f.write(b"\x12\x34\x56\x78BadLine\n")
    f.write(b"TX:6 VAL:100\n")
'

chown -R user:user /home/user
chmod -R 777 /home/user
