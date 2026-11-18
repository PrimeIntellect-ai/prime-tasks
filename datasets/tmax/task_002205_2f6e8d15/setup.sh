#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest biopython scipy numpy flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/app', exist_ok=True)

# Generate /app/reference_freqs.csv
with open('/app/reference_freqs.csv', 'w') as f:
    f.write("frequency\n")
    for _ in range(50):
        f.write(f"{random.gauss(125.0, 2.0)}\n")

# Create a mock sim_spectrometer in C, compile and strip it
c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *fin = fopen(argv[1], "r");
    if (!fin) return 1;

    char seq[1024] = {0};
    char line[256];
    while (fgets(line, sizeof(line), fin)) {
        if (line[0] != '>') {
            strncat(seq, line, 255);
        }
    }
    fclose(fin);

    // Hash sequence to get base frequency
    double base_freq = 0;
    for(int i=0; i<strlen(seq); i++) {
        if (seq[i] >= 'A' && seq[i] <= 'Z') base_freq += seq[i];
    }
    base_freq = fmod(base_freq, 50.0) + 100.0; 

    srand(time(NULL) ^ rand());
    double noise_freq = base_freq + ((rand() % 100) / 50.0 - 1.0); // +/- 1.0 Hz noise

    FILE *fout = fopen(argv[2], "w");
    fprintf(fout, "time,amplitude\\n");
    for(int i=0; i<1000; i++) {
        double t = i * 0.001;
        double amp = sin(2 * M_PI * noise_freq * t) + ((rand()%100)/500.0);
        fprintf(fout, "%f,%f\\n", t, amp);
    }
    fclose(fout);
    return 0;
}
"""
with open('/tmp/sim.c', 'w') as f: f.write(c_code)
os.system("gcc -O2 /tmp/sim.c -o /app/sim_spectrometer -lm && strip /app/sim_spectrometer")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py /tmp/sim.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
