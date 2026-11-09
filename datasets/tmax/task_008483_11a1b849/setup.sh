#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc gawk
    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin /home/user/scripts /home/user/data

    cat << 'EOF' > /home/user/src/pdf_eval.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <x>\n", argv[0]);
        return 1;
    }
    double x = atof(argv[1]);
    // Custom PDF: f(x) = exp(-x^2 / 2) * (1 + sin(5*x)^2)
    double val = exp(-x*x / 2.0) * (1.0 + pow(sin(5.0 * x), 2));
    printf("%.6f\n", val);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
