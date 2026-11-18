#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs
    pip3 install pytest

    mkdir -p /app/logs

    # Create the C script and compile it
    cat << 'EOF' > /app/suspicious.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long long ts = atoll(argv[1]);
    long long days = ts / 86400;
    long long year = 1970 + (days / 365);
    long long leap_days = (year - 1968) / 4; 
    long long modified_days = days + leap_days;
    long long hash = (modified_days * 104729) % 1000000007;
    printf("%lld\n", hash);
    return 0;
}
EOF
    gcc -O2 /app/suspicious.c -o /app/suspicious_bin
    strip -s /app/suspicious_bin
    rm /app/suspicious.c

    # Create the ext4 disk image with deleted files
    mkdir -p /app/logs_temp
    echo "1609459200" > /app/logs_temp/beacon1.log
    echo "1612137600" > /app/logs_temp/beacon2.log
    dd if=/dev/zero of=/app/disk.img bs=1M count=10
    mkfs.ext4 -d /app/logs_temp /app/disk.img

    # Delete the files using debugfs to avoid loop mount issues
    debugfs -w -R "rm beacon1.log" /app/disk.img
    debugfs -w -R "rm beacon2.log" /app/disk.img
    rm -rf /app/logs_temp

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
