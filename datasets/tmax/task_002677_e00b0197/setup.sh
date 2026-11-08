#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc liblapacke-dev
    pip3 install pytest numpy

    mkdir -p /app
    cat << 'EOF' > /app/oracle.py
import sys
import numpy as np

def fit_circle(csv_file):
    try:
        coords = np.loadtxt(csv_file, delimiter=',')
        if len(coords) == 0:
            return
        # Center points
        mean = np.mean(coords, axis=0)
        centered = coords - mean

        # SVD
        U, S, Vt = np.linalg.svd(centered, full_matrices=False)

        # Project to 2D
        basis = Vt[:2, :]
        proj = centered @ basis.T

        # Kasa fit: x^2 + y^2 = 2ax + 2by + c
        x = proj[:, 0]
        y = proj[:, 1]
        z = x**2 + y**2

        A = np.column_stack((2*x, 2*y, np.ones_like(x)))
        res, _, _, _ = np.linalg.lstsq(A, z, rcond=None)
        a, b, c = res

        R = np.sqrt(a**2 + b**2 + c)
        print(f"Radius: {R:.4f}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    if len(sys.argv) > 1:
        fit_circle(sys.argv[1])
EOF

    cat << 'EOF' > /app/circle_fitter
#!/bin/bash
python3 /app/oracle.py "$1"
EOF
    chmod +x /app/circle_fitter

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
