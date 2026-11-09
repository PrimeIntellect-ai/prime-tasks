#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pandas scipy

mkdir -p /home/user/data
mkdir -p /app/bio_kinetics/bio_kinetics

cat << 'EOF' > /home/user/data/spectroscopy.csv
time,signal
0.0,0.000000
0.2,0.370409
0.4,0.540450
0.6,0.613941
0.8,0.630048
1.0,0.614838
1.2,0.582490
1.4,0.541416
1.6,0.496515
1.8,0.450702
2.0,0.406001
2.2,0.363574
2.4,0.324103
2.6,0.287957
2.8,0.255259
3.0,0.225965
3.2,0.199850
3.4,0.176646
3.6,0.156066
3.8,0.137834
4.0,0.121696
4.2,0.107412
4.4,0.094770
4.6,0.083590
4.8,0.073711
5.0,0.064993
EOF

cat << 'EOF' > /app/bio_kinetics/setup.py
from setuptools import setup, find_packages
setup(
    name='bio_kinetics',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['numpy'],
)
EOF

cat << 'EOF' > /app/bio_kinetics/bio_kinetics/__init__.py
from .solver import simulate_B
EOF

cat << 'EOF' > /app/bio_kinetics/bio_kinetics/solver.py
import numpy as np

def simulate_B(k1, k2, t_eval):
    def derivatives(t, y):
        A, B = y
        return np.array([-k1*A, k1*A - k2*B])

    t_eval = np.asarray(t_eval)
    y_out = np.zeros(len(t_eval))

    y = np.array([1.0, 0.0])
    t = 0.0
    h = 0.01
    tol = 1e-5

    idx = 0
    if t_eval[0] == 0:
        y_out[0] = y[1]
        idx = 1

    while idx < len(t_eval):
        t_target = t_eval[idx]

        while t < t_target:
            h = min(h, t_target - t)

            k1_y = derivatives(t, y)
            y_tmp = y + h * k1_y
            k2_y = derivatives(t + h, y_tmp)

            y_next = y + (h/2) * (k1_y + k2_y)
            y_euler = y + h * k1_y

            err = np.max(np.abs(y_next - y_euler)) + 1e-15

            # INTENTIONAL BUG: inverted step-size adaptation
            h_new = h * 0.9 * np.sqrt(err / tol)

            if err <= tol:
                t += h
                y = y_next

            h = max(1e-6, min(h_new, 0.5))

        y_out[idx] = y[1]
        idx += 1

    return y_out
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/data /app/bio_kinetics
chmod -R 777 /home/user
