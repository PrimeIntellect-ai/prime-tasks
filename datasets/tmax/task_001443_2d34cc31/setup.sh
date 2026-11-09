#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double x = atof(argv[1]);
    if (x < 0) return 1;
    double result = 1.0 / (sqrt(x + 1.0) + sqrt(x));
    printf("%.15f\n", result);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_calc -lm
    strip -s /app/oracle_calc
    rm /app/oracle.c

    # Create ext4 image with deleted file without loop mounting
    mkdir -p /tmp/dev_drive
    echo "The original function is meant to compute the difference between the square root of (x+1) and the square root of x. Watch out for catastrophic cancellation at large x!" > /tmp/dev_drive/notes.txt

    dd if=/dev/zero of=/home/user/dev_drive.img bs=1M count=10
    mke2fs -t ext4 -d /tmp/dev_drive /home/user/dev_drive.img
    debugfs -w -R "rm notes.txt" /home/user/dev_drive.img

    chmod 644 /home/user/dev_drive.img
    chmod -R 777 /home/user
