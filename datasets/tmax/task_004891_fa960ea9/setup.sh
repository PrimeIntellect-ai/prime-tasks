#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy networkx flask fastapi uvicorn requests pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.py
import numpy as np
import sys
import csv

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    matrix = []
    with open(sys.argv[1], 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            matrix.append([float(x) for x in row])

    A = np.array(matrix)
    L = np.diag(A.sum(axis=1)) - A
    eigenvalues = np.linalg.eigvals(L)

    if np.any(np.abs(eigenvalues) < 1e-5):
        # Simulate the crash on near-singular/disconnected input
        sys.exit(1)

    # Dummy embedding extraction (e.g. dominant eigenvector of A)
    w, v = np.linalg.eig(A)
    dominant_v = v[:, np.argmax(w)].real
    print(",".join(map(str, dominant_v.tolist())))

if __name__ == "__main__":
    main()
EOF

    pyinstaller --onefile --distpath /app --name matrix_oracle /tmp/oracle.py
    chmod +x /app/matrix_oracle
    rm -rf /tmp/oracle.py build matrix_oracle.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
