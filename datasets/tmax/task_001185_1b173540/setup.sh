#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/math_project

    cat << 'EOF' > /home/user/math_project/libmathparse.c
#include <stdio.h>
#include <stdlib.h>
#include "libmathparse.h"

// Parses a hex string where the first byte (2 hex chars) is the number of elements N.
// The next N bytes (2*N hex chars) are the elements to sum.
double process_data(const char* hex) {
    unsigned int len;
    sscanf(hex, "%02x", &len);

    unsigned int *vals = malloc(len * sizeof(unsigned int));
    if (!vals) return 0.0;

    // BUG: Off-by-one error causes a heap buffer overflow (i <= len instead of i < len)
    for(int i = 0; i <= len; i++) {
        sscanf(hex + 2 + i*2, "%02x", &vals[i]);
    }

    double sum = 0;
    for(int i = 0; i < len; i++) {
        sum += vals[i];
    }

    free(vals);
    return sum;
}
EOF

    cat << 'EOF' > /home/user/math_project/libmathparse.h
#ifndef LIBMATHPARSE_H
#define LIBMATHPARSE_H

double process_data(const char* hex);

#endif
EOF

    cat << 'EOF' > /home/user/math_project/main.c
#include <stdio.h>
#include "libmathparse.h"

int main() {
    // 05 elements: 10, 20, 30, 40, 50 (in hex: 0A, 14, 1E, 28, 32)
    // Encoded string: "050A141E2832"
    const char* data = "050A141E2832";

    double result = process_data(data);

    FILE *f = fopen("/home/user/math_project/result.txt", "w");
    if(f) {
        fprintf(f, "%.2f\n", result);
        fclose(f);
    } else {
        printf("Failed to open file for writing.\n");
        return 1;
    }

    printf("Result written successfully.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_project/Makefile
all: libmathparse.so main

libmathparse.so: libmathparse.c
	gcc -shared -fPIC -o libmathparse.so libmathparse.c

main: main.c
	gcc -o main main.c -L. -lmathparse
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
