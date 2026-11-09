#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/ticket_882

    cat << 'EOF' > /home/user/ticket_882/factorize.c
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

void print_factors(int n) {
    int factors[8]; // Buffer too small for numbers with many factors
    int count = 0;
    int temp = n;

    for (int i = 2; i <= temp; i++) {
        while (temp % i == 0) {
            // Intermediate validation
            assert(count < 8);
            factors[count++] = i;
            temp /= i;
        }
    }

    printf("%d: ", n);
    for(int i = 0; i < count; i++) {
        printf("%d ", factors[i]);
    }
    printf("\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <number>\n", argv[0]);
        return 1;
    }
    int num = atoi(argv[1]);
    if (num < 2) {
        fprintf(stderr, "Number must be > 1\n");
        return 1;
    }
    print_factors(num);
    return 0;
}
EOF

    cd /home/user/ticket_882
    gcc -o factorize factorize.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
