#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    # Create signal.dat
    python3 -c "
import numpy as np
t = np.linspace(0, 10, 1000)
# Dominant freq = 2.45 Hz
y = np.sin(2 * np.pi * 2.45 * t) + np.random.normal(0, 0.2, 1000)
with open('signal.dat', 'w') as f:
    for i in range(1000):
        f.write(f'{t[i]:.4f} {y[i]:.4f}\n')
"

    # Create legacy_fft.out
    echo "2.450" > /home/user/legacy_fft.out

    # Create fft.py
    cat << 'EOF' > /home/user/fft.py
import sys
import numpy as np

data = np.loadtxt(sys.stdin)
t = data[:, 0]
y = data[:, 1]

n = len(y)
dt = t[1] - t[0]
yf = np.fft.rfft(y)
xf = np.fft.rfftfreq(n, d=dt)

# Get dominant frequency
idx = np.argmax(np.abs(yf))
print(f"{xf[idx]:.3f}")
EOF
    chmod +x /home/user/fft.py

    # Create analytical_model.py
    cat << 'EOF' > /home/user/analytical_model.py
import sys
x = float(sys.argv[1])
# Unstable function near 1.0
if abs(x - 1.0) < 1e-9:
    print("10.0")
else:
    print(f"{10.0 + 1.0/(abs(x - 1.0)):.4f}")
EOF
    chmod +x /home/user/analytical_model.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
