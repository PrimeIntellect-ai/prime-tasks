#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    mkdir -p /home/user/calc_service
    cd /home/user/calc_service
    git init
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    # Commit 1: Initial working, but mathematically unstable version
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    double x = atof(argv[1]);
    int steps = 0;

    // Stable loop condition
    while (steps < 10) {
        double diff = sqrt(x * x + 1.0) - x;
        x = x - 1.0 / diff;
        steps++;
    }

    printf("%.6f\n", x);
    return 0;
}
EOF
    git add calc.c
    git commit -m "Initial commit of calculation service"

    # Commit 2: Accidental leak
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// TODO: Use secure vault, don't hardcode!
const char* API_KEY = "sk_live_9f8e7d6c5b4a3f2e1d0c";

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    double x = atof(argv[1]);
    int steps = 0;

    while (steps < 10) {
        double diff = sqrt(x * x + 1.0) - x;
        x = x - 1.0 / diff;
        steps++;
    }

    printf("%.6f\n", x);
    return 0;
}
EOF
    git add calc.c
    git commit -m "Add API key for upstream service"

    # Commit 3: Panic removal
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    double x = atof(argv[1]);
    int steps = 0;

    while (steps < 10) {
        double diff = sqrt(x * x + 1.0) - x;
        x = x - 1.0 / diff;
        steps++;
    }

    printf("%.6f\n", x);
    return 0;
}
EOF
    git add calc.c
    git commit -m "Remove API key"

    # Commit 4: Bug introduced (while loop changing to x != prev)
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    double x = atof(argv[1]);
    double prev = -1.0;

    // Change to convergence loop instead of fixed steps
    while (x != prev) {
        prev = x;
        double diff = sqrt(x * x + 1.0) - x;
        x = x - 1.0 / diff;
    }

    printf("%.6f\n", x);
    return 0;
}
EOF
    git add calc.c
    git commit -m "Change to convergence loop for higher accuracy"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
