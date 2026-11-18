#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc e2tools e2fsprogs gawk
pip3 install pytest

mkdir -p /app

# Create the naive variance calculation binary
cat << 'EOF' > /tmp/variance_calc.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    float sum = 0.0f;
    float sum_sq = 0.0f;
    float val;
    int n = 0;

    while (scanf("%f", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        n++;
    }

    if (n < 2) {
        printf("0.0\n");
        return 0;
    }

    float variance = (sum_sq - (sum * sum) / n) / (n - 1);
    printf("%.4f\n", variance);
    return 0;
}
EOF

gcc -O2 /tmp/variance_calc.c -o /app/variance_calc
strip /app/variance_calc
rm /tmp/variance_calc.c

# Create the ext4 filesystem image
dd if=/dev/zero of=/app/data.img bs=1M count=10
mkfs.ext4 -F /app/data.img

# Create the latency log file
cat << 'EOF' > /tmp/latency_data.log
2023-10-01T12:00:00Z|1000042.12
2023-10-01T12:00:01Z,1000043.15 garbage
2023-10-01T12:00:02Z 1000041.99
2023-10-01T12:00:03Z|1000045.00
EOF

# Copy the file into the image and then delete it to simulate accidental deletion
e2cp /tmp/latency_data.log /app/data.img:/latency_data.log
e2rm /app/data.img:/latency_data.log
rm /tmp/latency_data.log

# Set up the user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
