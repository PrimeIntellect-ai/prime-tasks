#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest numpy h5py

mkdir -p /app
mkdir -p /home/user

# Create the C source for the binary
cat << 'EOF' > /tmp/model_exec.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double x = atof(argv[1]);
    double y = (x * x * x) - (2.0 * x * x) + x;
    printf("%.8f\n", y);
    return 0;
}
EOF

# Compile and strip the binary
gcc -O2 /tmp/model_exec.c -o /app/model_exec
strip /app/model_exec
rm /tmp/model_exec.c
chmod +x /app/model_exec

# Create the HDF5 file with test data
cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

# Fixed seed for data generation
np.random.seed(123)
measurements = np.random.uniform(-5, 5, 50)

with h5py.File('/home/user/experiment.h5', 'w') as f:
    f.create_dataset('measurements', data=measurements)

EOF
python3 /tmp/setup_data.py
rm /tmp/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
