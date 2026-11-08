#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    # Create the oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    double a = atof(argv[1]);
    double b = atof(argv[2]);
    double result = 42.0 * (a * b) / (a + b + 0.001);
    printf("%f\n", result);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_bin
    strip /app/oracle_bin
    rm /app/oracle.c

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the git repository
    mkdir -p /home/user/service_repo
    cd /home/user/service_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1
    cat << 'EOF' > service.py
import time
def compute(a, b):
    return 42.0 * (a * b) / (a + b + 0.001)
EOF
    git add service.py
    git commit -m "Initial commit"

    # Commits 2-100
    for i in $(seq 2 100); do
        echo "# comment $i" >> service.py
        git commit -am "Commit $i"
    done

    # Commit 101: introduce race condition
    cat << 'EOF' > service.py
import time
temp_val = 0.0
def compute(a, b):
    global temp_val
    temp_val = a * b
    time.sleep(0.01)
    return 42.0 * temp_val / (a + b + 0.001)
EOF
    git commit -am "Commit 101: refactor caching"

    # Commits 102-200
    for i in $(seq 102 200); do
        echo "# comment $i" >> service.py
        git commit -am "Commit $i"
    done

    # Final permissions
    chmod -R 777 /home/user
