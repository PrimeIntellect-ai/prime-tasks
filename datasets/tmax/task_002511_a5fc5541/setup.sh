#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/clustering

    cat << 'EOF' > /home/user/clustering/generate_data.py
import struct
import random
random.seed(42)
with open('/home/user/clustering/data.bin', 'wb') as f:
    for _ in range(33): f.write(struct.pack('d', random.gauss(10.0, 2.0)))
    for _ in range(33): f.write(struct.pack('d', random.gauss(50.0, 2.0)))
    for _ in range(34): f.write(struct.pack('d', random.gauss(90.0, 2.0)))
EOF
    python3 /home/user/clustering/generate_data.py
    rm /home/user/clustering/generate_data.py

    cat << 'EOF' > /home/user/clustering/cluster.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>

#define NUM_POINTS 100
#define K 3
#define MAX_ITER 100

int main() {
    double points[NUM_POINTS];
    double centroids[K] = {0.0, 50.0, 100.0};
    int counts[K];

    // BUG 1: Assumes read returns all bytes at once.
    // When reading from a pipe, it might return partial data.
    size_t expected_bytes = NUM_POINTS * sizeof(double);
    ssize_t bytes_read = read(STDIN_FILENO, points, expected_bytes);

    if (bytes_read <= 0) {
        fprintf(stderr, "Failed to read data\n");
        return 1;
    }

    int actual_points = bytes_read / sizeof(double);

    for (int iter = 0; iter < MAX_ITER; iter++) {
        double new_centroids[K] = {0};
        for (int i = 0; i < K; i++) counts[i] = 0;

        for (int i = 0; i < actual_points; i++) {
            double p = points[i];
            int best_k = 0;
            double min_dist = fabs(p - centroids[0]);

            for (int j = 1; j < K; j++) {
                double dist = fabs(p - centroids[j]);
                if (dist < min_dist) {
                    min_dist = dist;
                    best_k = j;
                }
            }
            new_centroids[best_k] += p;
            counts[best_k]++;
        }

        int converged = 1;
        for (int i = 0; i < K; i++) {
            // BUG 2: Division by zero if count is 0 (which happens if partial read misses points)
            double updated = new_centroids[i] / counts[i];
            if (fabs(updated - centroids[i]) > 1e-4) {
                converged = 0;
            }
            centroids[i] = updated;
        }

        if (converged) break;
    }

    for (int i = 0; i < K; i++) {
        printf("Centroid %d: %.4f\n", i, centroids[i]);
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/run_tests.sh
#!/bin/bash
cd /home/user/clustering

gcc -o cluster cluster.c -lm

FAILURES=0
for i in {1..10}; do
    # Simulate slow pipe to trigger the read bug
    (dd if=data.bin bs=16 count=10 2>/dev/null; sleep 0.1; dd if=data.bin bs=16 skip=10 2>/dev/null) | ./cluster > test_out.txt
    if grep -q "NaN" test_out.txt || grep -q "nan" test_out.txt; then
        echo "Test $i: FAILURE (NaN detected)"
        FAILURES=$((FAILURES+1))
    else
        echo "Test $i: SUCCESS"
    fi
done

if [ $FAILURES -gt 0 ]; then
    echo "Total Failures: $FAILURES"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
EOF

    chmod +x /home/user/run_tests.sh
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
