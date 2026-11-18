#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /app /home/user/project

    # 1. Create and compile the oracle binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t compute_seq(uint32_t n, uint32_t acc) {
    if (n == 0) return acc;
    if (n % 2 == 0) return compute_seq(n / 2, acc + n);
    return compute_seq(n - 1, acc ^ n);
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    uint32_t n = atoi(argv[1]);
    printf("%u\n", compute_seq(n, 0));
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_bin
    strip /app/oracle_bin
    rm /tmp/oracle.c
    chmod +x /app/oracle_bin

    # 2. Create the broken project for the agent
    cat << 'EOF' > /home/user/project/Makefile
solution: main.o compute.o
	gcc -o solution main.o compute.o

main.o: main.c
	gcc -g -c main.c

compute.o: compute.c
	gcc -g -c compute.c

clean:
	rm -f *.o solution
EOF

    cat << 'EOF' > /home/user/project/compute.h
#ifndef COMPUTE_H
#define COMPUTE_H
#include <stdint.h>

uint32_t compute_seq(uint32_t n, uint32_t acc);

#endif
EOF

    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include <stdlib.h>
#include "compute.h"

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <num>\n", argv[0]);
        return 1;
    }
    uint32_t n = atoi(argv[1]);
    printf("%u\n", compute_seq(n, 0));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/compute.c
#include "compute.h"

uint32_t compute(uint32_t n, uint32_t acc) {
    if (n == 0) return acc;
    if (n % 2 == 0) {
        return compute(n / 2, acc + n);
    } else {
        return compute(n + 1, acc ^ n); // BUG: n+1 leads to stack overflow
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
