#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

# Create directories
mkdir -p /app/vendored/c_matrix_lib-1.0
mkdir -p /app/tests/corpus/evil
mkdir -p /app/tests/corpus/clean

# Create C source file
cat << 'EOF' > /app/vendored/c_matrix_lib-1.0/matrix.c
double calculate_determinant(double* matrix, int n) {
    if (n == 2) {
        return matrix[0]*matrix[3] - matrix[1]*matrix[2];
    } else if (n == 3) {
        return matrix[0]*(matrix[4]*matrix[8] - matrix[5]*matrix[7])
             - matrix[1]*(matrix[3]*matrix[8] - matrix[5]*matrix[6])
             + matrix[2]*(matrix[3]*matrix[7] - matrix[4]*matrix[6]);
    }
    return 0.0;
}
EOF

# Create Makefile (missing -fPIC)
printf "CC=gcc\nCFLAGS=-Wall -O2\n\nlibmatrix.so: matrix.c\n\t\$(CC) \$(CFLAGS) -shared -o libmatrix.so matrix.c\n" > /app/vendored/c_matrix_lib-1.0/Makefile

# Generate sample corpus files
cat << 'EOF' > /app/tests/corpus/evil/evil_1.json
{"filename": "evil_1.json", "n": 2, "data": [1.0, 2.0, 2.0, 4.0]}
EOF

cat << 'EOF' > /app/tests/corpus/clean/clean_1.json
{"filename": "clean_1.json", "n": 2, "data": [1.0, 2.0, 3.0, 4.0]}
EOF

# Setup user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
