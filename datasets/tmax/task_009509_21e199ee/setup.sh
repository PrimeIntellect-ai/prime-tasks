#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make bc gawk
    pip3 install pytest

    mkdir -p /home/user/risk_job

    cat << 'EOF' > /home/user/risk_job/calc_metrics.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Computes f(x) = x^3 - 5x - 9 and f'(x) = 3x^2 - 5
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double x = atof(argv[1]);
    double fx = pow(x, 3) - 5 * x - 9;
    double fdx = 3 * pow(x, 2) - 5;
    printf("%f %f\n", fx, fdx);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/risk_job/Makefile
calc_metrics: calc_metrics.c
	gcc -o calc_metrics calc_metrics.c
EOF

    cat << 'EOF' > /home/user/risk_job/run_job.sh
#!/bin/bash

cd /home/user/risk_job
make || exit 1

X=5.0
TOL="0.0001"
MAX_ITER=20

for (( i=1; i<=MAX_ITER; i++ )); do
    # Read f(x) and f'(x) from helper
    read -r FX FDX <<< $(./calc_metrics $X)

    # Calculate delta
    DELTA=$(echo "$FX / $FDX" | bc)
    X=$(echo "$X - $DELTA" | bc)

    # Assertion: check convergence (absolute value of delta)
    ABS_DELTA=$(echo "$DELTA" | awk '{print ($1 < 0) ? -$1 : $1}')

    # Bug: Bash cannot compare floats natively
    if [ "$ABS_DELTA" -lt "$TOL" ]; then
        echo "Converged at $X" > /home/user/risk_job/success.log
        exit 0
    fi
done

echo "Convergence failure!" >&2
exit 1
EOF

    chmod +x /home/user/risk_job/run_job.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
