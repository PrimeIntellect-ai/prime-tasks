#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>

int main() {
    double window[5];
    int count = 0;
    double val;
    while (scanf("%lf", &val) == 1) {
        window[count % 5] = val;
        count++;
        if (count < 5) {
            printf("0.000000\n");
        } else {
            double y[5];
            for (int i=0; i<5; i++) {
                y[i] = window[(count - 5 + i) % 5];
            }
            double sum_x = 10.0; // 0+1+2+3+4
            double sum_x2 = 30.0; // 0+1+4+9+16
            double sum_y = 0;
            double sum_xy = 0;
            for (int i=0; i<5; i++) {
                sum_y += y[i];
                sum_xy += i * y[i];
            }
            double m = (5.0 * sum_xy - sum_x * sum_y) / (5.0 * sum_x2 - sum_x * sum_x);
            printf("%.6f\n", m);
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/profiler_baseline
    strip /app/profiler_baseline
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
