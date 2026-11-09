#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/jacobian_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    double x = atof(argv[1]);
    double y = atof(argv[2]);
    double m[9];
    m[0] = cos(x) * (y + 1.0);
    m[1] = -sin(x) * (y + 1.0);
    m[2] = x * y;
    m[3] = sin(x) * (y + 1.0);
    m[4] = cos(x) * (y + 1.0);
    m[5] = x + y;
    m[6] = 0.1;
    m[7] = 0.2;
    m[8] = exp(-(x*x + y*y));

    printf("%f %f %f %f %f %f %f %f %f\n", 
           m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]);
    return 0;
}
EOF
    gcc /tmp/jacobian_oracle.c -o /app/jacobian_oracle -lm -s
    chmod +x /app/jacobian_oracle
    rm /tmp/jacobian_oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
