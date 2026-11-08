#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc rustc libc6-dev
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/calc.c
#include <stdio.h>
#include <stdlib.h>

double evaluate_addition(const char* expr) {
    int a = 0, b = 0;
    if (sscanf(expr, "%d + %d", &a, &b) == 2) {
        return (double)(a + b);
    }
    return 0.0;
}
EOF

cat << 'EOF' > /home/user/requests.txt
1 + 1
# This is a comment
10 + 20
100 + 200
1000 + 20000000 # Invalid: longer than 15 characters
5 + 5
8 + 8
EOF

chmod 644 /home/user/calc.c
chmod 644 /home/user/requests.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
