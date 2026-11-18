#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int prev = 0;
    int curr;
    while (scanf("%d", &curr) == 1) {
        if (prev == 837 && curr == 912) {
            void *ptr = malloc(1024);
            // Intentionally not freed to simulate a leak on a specific anomaly
            (void)ptr; 
        }
        prev = curr;
    }
    return 0;
}
EOF

    gcc -g -o /home/user/service /home/user/service.c

    gawk -v seed=12345 'BEGIN {
        srand(seed);
        for(i=1; i<=1000; i++) {
            if(i == 742) print 837;
            else if(i == 743) print 912;
            else print int(rand() * 10000);
        }
    }' > /home/user/input.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
