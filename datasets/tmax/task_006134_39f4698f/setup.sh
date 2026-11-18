#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_gen.c
#include <stdio.h>

int main() {
    FILE *f = fopen("/home/user/network.csv", "w");
    if (f == NULL) return 1;
    // Rate matrix R
    fprintf(f, "-0.5, 0.0, 0.0, 0.0\n");
    fprintf(f, "0.5, -0.3, 0.0, 0.0\n");
    fprintf(f, "0.0, 0.3, -0.1, 0.0\n");
    fprintf(f, "0.0, 0.0, 0.1, 0.0\n");
    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
