#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc
    pip3 install pytest

    mkdir -p /home/user/risk_engine
    cd /home/user/risk_engine

    git init

    # Commit 1: Introduce the secret and working (but maybe unoptimized) code
    cat << 'EOF' > calc_variance.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define CALIB_SECRET "TRADEX-9922-8811-SECRET"

int main() {
    printf("Secret: %s\n", CALIB_SECRET);
    return 0;
}
EOF
    git add calc_variance.c
    git config user.email "dev@example.com"
    git config user.name "Dev"
    git commit -m "Initial commit with secret"

    # Commit 2: Remove secret, add unstable variance calculation and break build (missing -lm)
    cat << 'EOF' > calc_variance.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    FILE *fp = fopen("data.txt", "r");
    if (!fp) return 1;

    double val;
    double sum = 0.0;
    double sum_sq = 0.0;
    int n = 0;

    while (fscanf(fp, "%lf", &val) == 1) {
        sum += val;
        sum_sq += val * val;
        n++;
    }
    fclose(fp);

    // Naive variance calculation, prone to catastrophic cancellation
    double variance = (sum_sq - (sum * sum) / n) / (n - 1);
    double stddev = sqrt(variance);

    printf("%.4f\n", stddev);
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -o calc_variance calc_variance.c
# Intentionally missing -lm for linker error
EOF
    chmod +x build.sh

    git add calc_variance.c build.sh
    git commit -m "Optimize variance calculation and remove secret"

    # Generate dataset that causes catastrophic cancellation in the naive algorithm
    cat << 'EOF' > data.txt
100000000.001
100000000.002
100000000.003
100000000.002
100000000.001
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
