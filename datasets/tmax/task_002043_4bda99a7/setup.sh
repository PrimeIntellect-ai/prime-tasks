#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx
    pip3 install pytest

    mkdir -p /home/user/libs
    mkdir -p /home/user/src

    touch /home/user/libs/libcatalan.so.1.0.5
    touch /home/user/libs/libcatalan.so.1.2.3
    touch /home/user/libs/libcatalan.so.1.1.9
    touch /home/user/libs/libcatalan.so.2.0.0-rc1
    touch /home/user/libs/libcatalan.so.0.9.9-beta

    cat << 'EOF' > /home/user/src/catalan.c
#include <stdio.h>
#include <stdlib.h>

unsigned long long catalan(int n) {
    if (n <= 1) return 1;
    unsigned long long res = 0;
    for (int i = 0; i < n; i++) {
        res += catalan(i) * catalan(n - i - 1);
    }
    return res;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    int n = atoi(argv[1]);
    printf("%llu\n", catalan(n));
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
