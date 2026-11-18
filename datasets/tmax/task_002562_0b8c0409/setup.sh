#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc libc6-dev fonts-dejavu
pip3 install pytest

mkdir -p /app
convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'DATA PROCESSING SPECIFICATION' text 20,100 'Formula: result = (x * 1000000000 + 42) XOR 0xDEADBEEF' text 20,150 'Note: All operations must be performed using 64-bit unsigned integers (uint64_t).' text 20,200 'Handle x=0 gracefully by returning exactly 3735928559.'" /app/spec.png

mkdir -p /home/user
cat << 'EOF' > /home/user/compute.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long long x = atoll(argv[1]);

    if (x == 0) {
        // Crash
        int *ptr = NULL;
        *ptr = 1;
    }

    int32_t intermediate = (int32_t)x * 1000000000; 
    int32_t result = intermediate + 42;

    uint64_t final_res = (uint64_t)result ^ 0xDEADBEEF;
    printf("%lu\n", final_res);
    return 0;
}
EOF

cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    uint64_t x = strtoull(argv[1], NULL, 10);
    if (x == 0) {
        printf("3735928559\n");
        return 0;
    }
    uint64_t intermediate = x * 1000000000ULL;
    uint64_t result = intermediate + 42ULL;
    uint64_t final_res = result ^ 0xDEADBEEFULL;
    printf("%lu\n", final_res);
    return 0;
}
EOF

gcc /app/oracle.c -o /app/oracle_compute
rm /app/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
