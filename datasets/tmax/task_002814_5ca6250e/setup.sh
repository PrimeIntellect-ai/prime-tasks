#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas numpy pyarrow fastparquet

    mkdir -p /home/user/data
    mkdir -p /app

    # Create the C source for the oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <sensor_val> <log_message>\n", argv[0]);
        return 1;
    }

    double sensor_val = atof(argv[1]);
    char *text = argv[2];

    // Logic: score = sensor_val + sum( len(word)^2 )
    // Tokenization is simple split by space.
    double token_metric = 0.0;
    int current_word_len = 0;
    int len = strlen(text);

    for (int i = 0; i <= len; i++) {
        if (text[i] == ' ' || text[i] == '\0') {
            if (current_word_len > 0) {
                token_metric += (current_word_len * current_word_len);
                current_word_len = 0;
            }
        } else {
            current_word_len++;
        }
    }

    double score = sensor_val * token_metric;
    printf("%.6f\n", score);
    return 0;
}
EOF

    gcc -O3 -s /tmp/oracle.c -o /app/feature_oracle
    chmod +x /app/feature_oracle

    # Generate the dataset using Python
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_rows = 500000

ids = np.arange(n_rows)
sensor_vals = np.random.normal(loc=50.0, scale=15.0, size=n_rows)

# Introduce NaNs
nan_indices = np.random.choice(n_rows, size=int(n_rows * 0.05), replace=False)
sensor_vals[nan_indices] = np.nan

# Introduce outliers
outlier_indices = np.random.choice(n_rows, size=int(n_rows * 0.01), replace=False)
sensor_vals[outlier_indices] = np.random.uniform(500, 1000, size=len(outlier_indices))

words = ["valve", "pressure", "stabilized", "pump", "error", "flow", "rate", "nominal", "warning", "high", "low", "temp"]
def generate_log():
    return " ".join(np.random.choice(words, size=np.random.randint(2, 8)))

log_messages = [generate_log() for _ in range(n_rows)]

df = pd.DataFrame({
    'id': ids,
    'sensor_val': sensor_vals,
    'log_message': log_messages
})

df.to_csv('/home/user/data/telemetry.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
