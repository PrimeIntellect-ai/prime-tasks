#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user/pipeline

    # 1. Create input.csv
    cat << 'EOF' > /home/user/pipeline/input.csv
1.5
2.5
3.5
4.5
5.5
6.5
7.5
8.5
9.5
10.5
EOF

    # 2. Create golden.csv (Expected output: input * 2.0 with float64 precision)
    cat << 'EOF' > /home/user/pipeline/golden.csv
3.0
5.0
7.0
9.0
11.0
13.0
15.0
17.0
19.0
21.0
EOF

    # 3. Create transform.py with the truncation bug
    cat << 'EOF' > /home/user/pipeline/transform.py
import sys
import os
import numpy as np

def process_data(input_file, output_file):
    precision_env = os.environ.get('NUMPY_PRECISION', '64')
    dtype = np.float32 if precision_env == '32' else np.float64

    with open(input_file, 'r') as f:
        data = [float(line.strip()) for line in f if line.strip()]

    arr = np.array(data, dtype=dtype)
    batch_size = int(os.environ.get('BATCH_SIZE', '3'))

    results = []
    # BUG: Truncates the last batch if not perfectly divisible
    num_full_batches = len(arr) // batch_size
    for i in range(num_full_batches):
        batch = arr[i*batch_size : (i+1)*batch_size]
        # Mathematical transformation: multiply by 2.0
        transformed = batch * 2.0
        results.extend(transformed)

    with open(output_file, 'w') as f:
        for val in results:
            f.write(f"{val}\n")

if __name__ == "__main__":
    process_data(sys.argv[1], sys.argv[2])
EOF

    # 4. Create build.sh with the precision bug
    cat << 'EOF' > /home/user/pipeline/build.sh
#!/bin/bash

# BUG: Wrong precision set here
export NUMPY_PRECISION=32
export BATCH_SIZE=3

python3 /home/user/pipeline/transform.py /home/user/pipeline/input.csv /home/user/pipeline/output.csv

# Diff analysis
if diff -q /home/user/pipeline/output.csv /home/user/pipeline/golden.csv; then
    echo "BUILD SUCCESS"
    exit 0
else
    echo "BUILD FAILED: Output does not match golden data."
    exit 1
fi
EOF

    chmod +x /home/user/pipeline/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
