#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat netcat-openbsd gawk
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/filter_oracle.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    float f1, f2, f3;
    if (scanf("%f,%f,%f", &f1, &f2, &f3) == 3) {
        if ((3.0 * f1) - (2.0 * f2) + f3 > 100.0) {
            printf("DIRTY\n");
        } else {
            printf("CLEAN\n");
        }
    }
    return 0;
}
EOF
    gcc -o /app/filter_oracle /tmp/filter_oracle.c
    strip /app/filter_oracle
    chmod +x /app/filter_oracle
    rm /tmp/filter_oracle.c

    mkdir -p /home/user/data
    python3 -c '
import random
with open("/home/user/data/raw_data.csv", "w") as f:
    for i in range(1, 500001):
        f1 = random.uniform(0, 100)
        f2 = random.uniform(0, 100)
        f3 = random.uniform(0, 100)
        payload = f"payload_{i}_{random.randint(1000,9999)}"
        f.write(f"{i},{f1:.2f},{f2:.2f},{f3:.2f},{payload}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
