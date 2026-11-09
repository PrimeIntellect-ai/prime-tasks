#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make gawk sed
pip3 install pytest pandas numpy

mkdir -p /home/user
mkdir -p /app/libspectral-0.1/src
mkdir -p /app/libspectral-0.1/bin

# Generate raw_signals.csv
cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
times = np.linspace(0, 1, 100)
data = {'Time': times}
for i in range(1000):
    data[f'Node_{i}'] = np.sin(2 * np.pi * (i+1) * times) + np.random.normal(0, 0.1, len(times))

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_signals.csv', index=False)

# Create a temporary long format for generating reference densities
long_df = df.melt(id_vars=['Time'], var_name='NodeID', value_name='Value')
long_df['NodeID'] = long_df['NodeID'].str.replace('Node_', '').astype(int)
long_df.to_csv('/tmp/long_signals.csv', index=False)
EOF
python3 /tmp/gen_data.py

# Create correct C code
cat << 'EOF' > /app/libspectral-0.1/src/spectral_density.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_NODES 1000

double re_arr[MAX_NODES] = {0};
double im_arr[MAX_NODES] = {0};
double mag_arr[MAX_NODES] = {0};

int main(int argc, char** argv) {
    if(argc < 3) return 1;
    FILE* in = fopen(argv[1], "r");
    if(!in) return 1;

    char line[256];
    if (fgets(line, sizeof(line), in) == NULL) { fclose(in); return 1; }
    while(fgets(line, sizeof(line), in)) {
        double t, v;
        int n;
        if (sscanf(line, "%lf,%d,%lf", &t, &n, &v) == 3) {
            if (n >= 0 && n < MAX_NODES) {
                re_arr[n] += v * cos(t);
                im_arr[n] += v * sin(t);
            }
        }
    }
    fclose(in);

    for(int i=0; i<MAX_NODES; i++) {
        double re = re_arr[i];
        double im = im_arr[i];
        double mag = sqrt(re*re + im*im);
        mag_arr[i] = mag;
    }

    FILE* out = fopen(argv[2], "w");
    if(!out) return 1;
    for(int i=0; i<MAX_NODES; i++) {
        fprintf(out, "%d,%lf\n", i, mag_arr[i]);
    }
    fclose(out);
    return 0;
}
EOF

# Create Makefile
cat << 'EOF' > /app/libspectral-0.1/Makefile
CC=gcc
CFLAGS=-O3 -Wall
LDFLAGS=-lm

all: bin/analyze_spectra

bin/analyze_spectra: src/spectral_density.c
	mkdir -p bin
	$(CC) $(CFLAGS) src/spectral_density.c -o bin/analyze_spectra $(LDFLAGS)

clean:
	rm -rf bin
EOF

# Compile and generate reference
cd /app/libspectral-0.1
make
./bin/analyze_spectra /tmp/long_signals.csv /app/reference_densities.txt

# Clean up and perturb
make clean
rm /tmp/long_signals.csv /tmp/gen_data.py

sed -i 's/double mag = sqrt(re\*re + im\*im);/double mag = sqrt(re + im);/g' /app/libspectral-0.1/src/spectral_density.c

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
chmod -R 777 /app
