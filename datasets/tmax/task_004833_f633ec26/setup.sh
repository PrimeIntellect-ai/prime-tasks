#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind file
    pip3 install pytest

    mkdir -p /home/user/polybuild/src
    mkdir -p /home/user/polybuild/include

    cat << 'EOF' > /home/user/polybuild/include/polyhash.h
#ifndef POLYHASH_H
#define POLYHASH_H

long long poly_hash(const char* str, int x);

#endif
EOF

    cat << 'EOF' > /home/user/polybuild/src/polyhash.c
#include "polyhash.h"
#include <stdlib.h>
#include <string.h>

long long poly_hash(const char* str, int x) {
    int len = strlen(str);
    int* coeffs = malloc(len * sizeof(int));
    for(int i = 0; i < len; i++) {
        coeffs[i] = (int)str[i];
    }

    long long result = 0;
    long long x_pow = 1;
    for(int i = 0; i < len; i++) {
        result += coeffs[i] * x_pow;
        x_pow *= x;
    }

    // BUG: missing memory deallocation
    return result;
}
EOF

    cat << 'EOF' > /home/user/polybuild/test_polyhash.c
#include <stdio.h>
#include "polyhash.h"

int main() {
    const char* test_str = "CI_CD_SUCCESS";
    int x = 3;
    long long result = poly_hash(test_str, x);

    FILE *f = fopen("result.txt", "w");
    if (f) {
        fprintf(f, "%lld\n", result);
        fclose(f);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/polybuild/Makefile
all: libpolyhash.so test_runner

libpolyhash.so: src/polyhash.o
	gcc -o libpolyhash.so src/polyhash.o

src/polyhash.o: src/polyhash.c
	gcc -I./include -c src/polyhash.c -o src/polyhash.o

test_runner: test_polyhash.c libpolyhash.so
	gcc -I./include test_polyhash.c -L. -lpolyhash -o test_runner
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
