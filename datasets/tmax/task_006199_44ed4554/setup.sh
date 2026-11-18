#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make
    pip3 install pytest

    mkdir -p /home/user/astro_calc
    cd /home/user/astro_calc
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1: Good state with high precision and secret
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <math.h>

#define CALIBRATION_SECRET 8.9875517923

int main() {
    double input = 2.5;
    double intermediate = pow(input, 3.0);
    double result = intermediate * CALIBRATION_SECRET;
    printf("Trajectory: %.7f\n", result);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
astro_calc: calc.c
	gcc -o astro_calc calc.c -lm
EOF

    git add calc.c Makefile
    git commit -m "Initial commit with high precision calibration secret"

    # Commit 2: Bad state with linker error and precision loss
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <math.h>

#define CALIBRATION_SECRET 8.98

int main() {
    float input = 2.5f;
    float intermediate = powf(input, 3.0f);
    float result = intermediate * CALIBRATION_SECRET;
    printf("Trajectory: %.7f\n", result);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
astro_calc: calc.c
	gcc -o astro_calc calc.c
EOF

    git add calc.c Makefile
    git commit -m "Optimize calculations and update Makefile"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
