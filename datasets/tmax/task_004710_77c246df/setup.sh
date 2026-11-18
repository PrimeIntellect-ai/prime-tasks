#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest websockets

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/algo.c
#include <stdio.h>

double compute_root(double n) {
    if (n < 0) return -1.0;
    double x = n;
    double y = 1.0;
    double e = 0.000001;
    while (x - y > e) {
        x = (x + y) / 2;
        y = n / x;
    }
    return x;
}

int main() {
    printf("%f\n", compute_root(25.0));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
CC = gcc
CFLAGS = -O2

all: algo

algo: algo.c
	$(CC) $(CFLAGS) -o algo algo.c

clean:
	rm -f algo libalgo.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
