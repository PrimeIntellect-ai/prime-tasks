#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc binutils libc6-dev
    pip3 install pytest

    # Create stripped binary
    mkdir -p /app
    cat << 'EOF' > /tmp/root_finder.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 6) return 1;
    double a = atof(argv[1]);
    double b = atof(argv[2]);
    double c = atof(argv[3]);
    double d = atof(argv[4]);
    double x0 = atof(argv[5]);

    for (int i=0; i<100; i++) {
        double f = a*x0*x0*x0 + b*x0*x0 + c*x0 + d;
        double df = 3*a*x0*x0 + 2*b*x0 + c;
        if (fabs(df) < 1e-9) {
            int *p = NULL;
            *p = 0; // Segfault
        }
        x0 = x0 - f/df;
    }
    printf("%f\n", x0);
    return 0;
}
EOF
    gcc -O3 /tmp/root_finder.c -o /app/root_finder -lm
    strip /app/root_finder
    rm /tmp/root_finder.c

    # Setup git repo
    mkdir -p /home/user/solver_repo
    cd /home/user/solver_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > wrapper.py
import subprocess

def solve(a, b, c, d, x0, max_iter=100):
    # Simulate wrapper logic
    if max_iter < 10:
        return False
    return True
EOF

    cat << 'EOF' > test_edge.py
from wrapper import solve
import sys

if not solve(1, -6, 11, -6, 0, max_iter=10):
    sys.exit(1)
sys.exit(0)
EOF

    git add wrapper.py test_edge.py
    git commit -m "Initial commit"

    for i in $(seq 1 5); do
        echo "# Good commit $i" >> wrapper.py
        git commit -am "Good commit $i"
    done

    # Bad commit
    cat << 'EOF' > wrapper.py
import subprocess

def solve(a, b, c, d, x0, max_iter=100):
    max_iter = 3 # hardcoded limit bug
    if max_iter < 10:
        return False
    return True
EOF
    git commit -am "Refactor wrapper"

    BAD_COMMIT=$(git rev-parse HEAD)
    echo "$BAD_COMMIT" > /home/user/.expected_bad_commit

    for i in $(seq 6 10); do
        echo "# Another commit $i" >> wrapper.py
        git commit -am "Another commit $i"
    done

    # Setup corpora
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/.hidden_corpora/clean
    mkdir -p /home/user/.hidden_corpora/evil

    echo "1,-6,11,-6,0" > /home/user/corpora/clean/1.csv
    echo "1,0,0,-1,2" > /home/user/corpora/clean/2.csv

    echo "1,0,0,-1,0" > /home/user/corpora/evil/1.csv
    echo "1,0,0,-1,foo" > /home/user/corpora/evil/2.csv

    cp -r /home/user/corpora/clean/* /home/user/.hidden_corpora/clean/
    cp -r /home/user/corpora/evil/* /home/user/.hidden_corpora/evil/

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
