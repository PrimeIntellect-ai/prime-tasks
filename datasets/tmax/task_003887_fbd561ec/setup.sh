#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc jq netcat-openbsd socat strace ltrace curl binutils
pip3 install pytest

mkdir -p /app/bin
cat << 'EOF' > /tmp/polycalc.c
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

int main(int argc, char *argv[]) {
    void *handle = dlopen("liblicense.so", RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "License check failed: missing liblicense.so\n");
        return 1;
    }

    int (*verify_license_key)(void) = dlsym(handle, "verify_license_key");
    if (!verify_license_key) {
        fprintf(stderr, "License check failed: invalid license library\n");
        return 1;
    }

    if (verify_license_key() != 1) {
        fprintf(stderr, "License check failed: invalid license\n");
        return 1;
    }

    if (argc != 3) {
        fprintf(stderr, "Usage: %s <x> <y>\n", argv[0]);
        return 1;
    }

    int x = atoi(argv[1]);
    int y = atoi(argv[2]);
    int result = 3 * x * x + 2 * y + 1;
    printf("%d\n", result);

    return 0;
}
EOF

gcc -O2 /tmp/polycalc.c -o /app/bin/polycalc -ldl
strip /app/bin/polycalc
rm /tmp/polycalc.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
