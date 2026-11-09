#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generator.c
#include <stdio.h>
int main() {
    double data[] = { -1.2, -0.5, 0.1, 0.3, 0.8, 1.1, -0.9 };
    for(int i=0; i<7; i++) {
        printf("%f\n", data[i]);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
