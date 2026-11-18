#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc build-essential upx-ucl
    pip3 install pytest numpy pandas

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/bin /app/corpora/clean /app/corpora/evil

    # Create stat_oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int compare_doubles(const void *a, const void *b) {
    double arg1 = *(const double *)a;
    double arg2 = *(const double *)b;
    if (arg1 < arg2) return -1;
    if (arg1 > arg2) return 1;
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[1024];
    double *losses = malloc(100000 * sizeof(double));
    int count = 0;
    int loss_idx = -1;

    if (fgets(line, sizeof(line), f)) {
        char *tok = strtok(line, ",\n");
        int idx = 0;
        while (tok) {
            if (strcmp(tok, "loss") == 0) loss_idx = idx;
            tok = strtok(NULL, ",\n");
            idx++;
        }
    }

    if (loss_idx == -1) loss_idx = 0;

    while (fgets(line, sizeof(line), f)) {
        char *tok = strtok(line, ",\n");
        int idx = 0;
        while (tok) {
            if (idx == loss_idx) {
                losses[count++] = atof(tok);
            }
            tok = strtok(NULL, ",\n");
            idx++;
        }
    }
    fclose(f);

    if (count == 0) {
        printf("0.0\n");
        return 0;
    }

    qsort(losses, count, sizeof(double), compare_doubles);
    double median = losses[count / 2];
    if (count % 2 == 0) median = (losses[count / 2 - 1] + losses[count / 2]) / 2.0;

    double *abs_devs = malloc(count * sizeof(double));
    for (int i = 0; i < count; i++) abs_devs[i] = fabs(losses[i] - median);
    qsort(abs_devs, count, sizeof(double), compare_doubles);

    double mad = abs_devs[count / 2];
    if (count % 2 == 0) mad = (abs_devs[count / 2 - 1] + abs_devs[count / 2]) / 2.0;

    double score = 1.0 / (1.0 + mad);
    printf("%f\n", score);

    free(losses);
    free(abs_devs);

    // Add some dummy data to make it compressible by UPX
    char dummy[10000];
    for(int i=0; i<10000; i++) dummy[i] = 'A' + (i % 26);
    if(argc > 999) printf("%s", dummy);

    return 0;
}
EOF

    gcc -O3 /tmp/oracle.c -o /app/bin/stat_oracle
    strip /app/bin/stat_oracle
    upx /app/bin/stat_oracle || true
    chmod +x /app/bin/stat_oracle

    # Generate corpora
    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

def make_clean(path, n_files=50):
    for i in range(n_files):
        losses = np.random.normal(2.0, 0.5, 500)
        # 5% missing
        mask = np.random.rand(500) < 0.05
        losses_str = ["" if m else str(l) for m, l in zip(mask, losses)]
        df = pd.DataFrame({"loss": losses_str})
        df.to_csv(os.path.join(path, f"clean_{i}.csv"), index=False)

def make_evil(path, n_files=50):
    for i in range(25):
        losses = np.random.normal(2.0, 5.0, 500)
        # inject outliers
        losses[np.random.choice(500, 5)] = np.random.normal(100, 10, 5)
        df = pd.DataFrame({"loss": losses})
        df.to_csv(os.path.join(path, f"evil_var_{i}.csv"), index=False)

    for i in range(25):
        # high MAD
        losses = np.random.normal(2.0, 0.5, 500)
        # shift half the data to increase MAD
        losses[:250] += 5.0
        # inject outliers
        losses[np.random.choice(500, 5)] = np.random.normal(100, 10, 5)
        df = pd.DataFrame({"loss": losses})
        df.to_csv(os.path.join(path, f"evil_mad_{i}.csv"), index=False)

make_clean("/app/corpora/clean")
make_evil("/app/corpora/evil")
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true

    # Ensure rust is available for user
    echo 'export PATH="/root/.cargo/bin:${PATH}"' >> /home/user/.bashrc

    chmod -R 777 /home/user
    chmod -R 777 /app
