#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/calc_interp.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        return 1;
    }
    char op = argv[1][0];
    int a = atoi(argv[2]);
    int b = atoi(argv[3]);

    if (op == '+') {
        printf("%d\n", a - b); // BUG: Should be a + b
    } else if (op == '-') {
        printf("%d\n", a - b);
    } else if (op == '*') {
        printf("%d\n", a * b);
    } else {
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/run_data.py
import sys
import subprocess

def process(filename):
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 3:
                out = subprocess.check_output(['./calc_interp', parts[0], parts[1], parts[2]])
                print "Result: " + out.strip()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/pipeline/data.csv
+,15,10
*,4,5
-,100,42
EOF

    chmod -R 777 /home/user
