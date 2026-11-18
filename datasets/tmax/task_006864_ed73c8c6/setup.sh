#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > math.cpp
int calculate(int a, int b) {
    return a + b * 2;
}
EOF

    g++ -fPIC -shared -o libmath.so math.cpp
    rm math.cpp

    cat << 'EOF' > main.c
#include <stdio.h>

int calculate(int a, int b);

int main() {
    printf("Result: %d\n", calculate(5, 3));
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
