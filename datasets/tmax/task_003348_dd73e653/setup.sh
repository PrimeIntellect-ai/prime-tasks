#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the binary
    mkdir -p /app
    cat << 'EOF' > /tmp/score_calc.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        return 1;
    }
    double v1 = atof(argv[1]);
    double v2 = atof(argv[2]);
    double v3 = atof(argv[3]);

    // High-level algorithm: 0.5*v1 + 1.2*v2 + 0.8*v3
    double score = (0.5 * v1) + (1.2 * v2) + (0.8 * v3);
    printf("%f\n", score);
    return 0;
}
EOF
    gcc -O3 -s /tmp/score_calc.c -o /app/score_calc
    rm /tmp/score_calc.c
    chmod +x /app/score_calc

    # 2. Create the data
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/batch1.csv
id,v1,v2,v3
1,1.0,2.0,3.0
2,4.0,5.0,6.0
3,0.1,0.2,0.3
EOF

    cat << 'EOF' > /home/user/data/test_batch.csv
id,v1,v2,v3
10,2.0,1.0,0.5
11,10.0,2.0,1.0
12,0.5,0.5,0.5
13,3.0,3.0,3.0
EOF

    chmod -R 777 /home/user
