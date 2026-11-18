#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy pandas

mkdir -p /home/user

cat << 'EOF' > /home/user/sequences.csv
SeqID,k_syn,Target_M
seq_1,2.5,1.2
seq_2,1.8,0.9
seq_3,3.0,1.5
seq_4,4.2,1.8
seq_5,1.1,0.5
EOF

cat << 'EOF' > /home/user/simulate.py
import sys
import numpy as np

def euler_integrate(k_syn, d, t_end=100, dt=0.5):
    # Naive Euler method - diverges for this stiff-ish non-linear system if dt is too large
    M = 0.0
    t = 0.0
    while t < t_end:
        dMdt = k_syn - d * (M**2)
        M += dMdt * dt
        t += dt
    return M

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python simulate.py <k_syn> <d>")
        sys.exit(1)
    k_syn = float(sys.argv[1])
    d = float(sys.argv[2])
    final_M = euler_integrate(k_syn, d)
    print(final_M)
EOF
chmod +x /home/user/simulate.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
