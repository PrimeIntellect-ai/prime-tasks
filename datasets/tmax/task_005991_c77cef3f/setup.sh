#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /home/user/bin /home/user/output

    cat << 'EOF' > /home/user/src/welford_ref.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    double count = 0, mean = 0, M2 = 0;
    double x;

    while (fscanf(f, "%lf", &x) == 1) {
        count += 1;
        double delta = x - mean;
        mean += delta / count;
        double delta2 = x - mean;
        M2 += delta * delta2;
    }

    fclose(f);

    if (count < 2) {
        printf("Not enough data.\n");
        return 1;
    }

    double variance = M2 / (count - 1);
    printf("Mean: %.10f\n", mean);
    printf("Sample Variance: %.10f\n", variance);

    return 0;
}
EOF

    python3 -c '
with open("/home/user/data/input.csv", "w") as f:
    for i in range(10000):
        val = 1000000000.0 + (i / 10000.0)
        f.write(f"{val}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
