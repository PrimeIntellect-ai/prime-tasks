#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential python3-h5py python3-numpy
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Create and compile instrument_oracle
    cat << 'EOF' > /app/instrument_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

double get_gain(double freq) {
    return 1.0 + 0.5 * sin(freq / 10.0) + 0.1 * cos(freq / 2.3);
}

int main(int argc, char** argv) {
    if (argc == 4 && strcmp(argv[1], "--batch") == 0) {
        FILE* fin = fopen(argv[2], "r");
        FILE* fout = fopen(argv[3], "w");
        double f;
        while(fscanf(fin, "%lf", &f) == 1) {
            fprintf(fout, "%.6f\n", get_gain(f));
        }
        fclose(fin);
        fclose(fout);
        return 0;
    }
    return 1;
}
EOF
    gcc -O3 /app/instrument_oracle.c -o /app/instrument_oracle -lm
    strip /app/instrument_oracle

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/spec-filter-src

    # Create spec-filter source code
    cat << 'EOF' > /home/user/spec-filter-src/filter.c
#include <stdio.h>
#include <stdlib.h>

#define WINDOW 5

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <input_signal.txt>\n", argv[0]);
        return 1;
    }
    FILE* fin = fopen(argv[1], "r");
    double vals[10000];
    int count = 0;
    while (fscanf(fin, "%lf", &vals[count]) == 1) {
        count++;
    }
    fclose(fin);

    for (int i = 0; i < count; i++) {
        double sum = 0;
        int w = 0;
        for (int j = i - WINDOW/2; j <= i + WINDOW/2; j++) {
            if (j >= 0 && j < count) {
                sum += vals[j];
                w++;
            }
        }
        printf("%.6f\n", sum / w);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/spec-filter-src/Makefile
spec-filter: filter.c
	gcc -O2 filter.c -o spec-filter
EOF

    # Generate raw spectra data
    cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np

np.random.seed(42)
freq = np.linspace(0, 100, 1000)
true_signal = 5.0 * np.exp(-((freq - 20)**2)/10) + 3.0 * np.exp(-((freq - 50)**2)/5) + 4.0 * np.exp(-((freq - 80)**2)/8)
gain = 1.0 + 0.5 * np.sin(freq / 10.0) + 0.1 * np.cos(freq / 2.3)
noise = np.random.normal(0, 0.2, size=len(freq))

measured_signal = true_signal * gain + noise

with h5py.File('/home/user/raw_spectra.h5', 'w') as f:
    f.create_dataset('freq', data=freq)
    f.create_dataset('signal', data=measured_signal)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
