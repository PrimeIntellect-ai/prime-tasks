#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc cargo curl strace xxd
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>

int main() {
    double count = 0.0;
    double mean = 0.0;
    double M2 = 0.0;
    double val;

    while (fread(&val, sizeof(double), 1, stdin) == 1) {
        count += 1.0;
        double delta = val - mean;
        mean += delta / count;
        double delta2 = val - mean;
        M2 += delta * delta2;
    }

    double variance = 0.0;
    if (count > 1.0) {
        variance = M2 / (count - 1.0);
    }

    fwrite(&mean, sizeof(double), 1, stdout);
    fwrite(&variance, sizeof(double), 1, stdout);
    return 0;
}
EOF

gcc -O3 /tmp/oracle.c -o /app/astro_filter
strip /app/astro_filter
rm /tmp/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
