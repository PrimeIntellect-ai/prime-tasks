#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the metrics.c file
    cat << 'EOF' > /home/user/metrics.c
#include <stdio.h>
#include <stdlib.h>

double total_metrics = 0.0;

void record_metric(double val) {
    total_metrics += val;
    FILE *f = fopen("/home/user/metrics.out", "w");
    if (f) {
        fprintf(f, "%.2f\n", total_metrics);
        fclose(f);
    }

    // Intentional memory leak for valgrind to catch
    void *leak = malloc(16);
    (void)leak; // suppress unused variable warning
}
EOF

    # Create the data.bin file in UTF-16LE
    printf "15.5 + 4.5\n100 / 4\n2 ** 4\n3 * 7\n" | iconv -f UTF-8 -t UTF-16LE > /home/user/data.bin

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
