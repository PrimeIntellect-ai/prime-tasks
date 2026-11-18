#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/trajectory

    cat << 'EOF' > /home/user/trajectory/calc.h
#ifndef CALC_H
#define CALC_H
double calculate_impact_time(double a, double b, double c);
#endif
EOF

    cat << 'EOF' > /home/user/trajectory/calc.c
#include <math.h>
#include "calc.h"

// Calculate smallest positive root of at^2 + bt + c = 0
double calculate_impact_time(double a, double b, double c) {
    float discriminant = (float)(b*b - 4*a*c);
    if (discriminant < 0) return -1.0;

    // Naive formula, suffers from catastrophic cancellation when b > 0 and 4ac is very small
    double t1 = (-b + sqrt(discriminant)) / (2.0*a);
    double t2 = (-b - sqrt(discriminant)) / (2.0*a);

    if (t1 > 0 && t2 > 0) return t1 < t2 ? t1 : t2;
    if (t1 > 0) return t1;
    if (t2 > 0) return t2;
    return -1.0;
}
EOF

    cat << 'EOF' > /home/user/trajectory/main.c
#include <stdio.h>
#include <stdlib.h>
#include "calc.h"

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <a> <b> <c>\n", argv[0]);
        return 1;
    }
    double a = atof(argv[1]);
    double b = atof(argv[2]);
    double c = atof(argv[3]);

    double result = calculate_impact_time(a, b, c);
    printf("%.10g\n", result);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/trajectory/build.sh
#!/bin/bash
# Missing the math library link (-lm)
gcc -O2 -o traj_calc main.c calc.c
EOF

    cat << 'EOF' > /home/user/trajectory/fuzzer.sh
#!/bin/bash
# Fuzzes the executable and checks against a python precise calculation

python3 -c "
import sys
import math
def check(a, b, c, expected):
    import subprocess
    try:
        out = subprocess.check_output(['./traj_calc', str(a), str(b), str(c)])
        val = float(out.decode().strip())
        if abs(val - expected) / expected > 1e-5:
            print(f'FAIL for {a} {b} {c}: expected {expected}, got {val}')
            sys.exit(1)
    except Exception as e:
        print('Error running traj_calc', e)
        sys.exit(1)

# Stable python implementation for test targets
def calc(a, b, c):
    disc = b*b - 4*a*c
    if disc < 0: return -1.0
    q = -0.5 * (b + (1 if b > 0 else -1) * math.sqrt(disc))
    t1 = q / a
    t2 = c / q
    roots = [t for t in (t1, t2) if t > 0]
    return min(roots) if roots else -1.0

# Normal case
check(1.0, -5.0, 6.0, 2.0)
# Extreme cases (catastrophic cancellation in naive implementation)
check(0.0001, 1000.0, 0.0001, calc(0.0001, 1000.0, 0.0001))
check(1e-5, 1e5, 1e-5, calc(1e-5, 1e5, 1e-5))

print('FUZZER PASSED')
"
EOF

    chmod +x /home/user/trajectory/build.sh
    chmod +x /home/user/trajectory/fuzzer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
