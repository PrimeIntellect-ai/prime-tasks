#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv bc gawk
    pip3 install pytest

    mkdir -p /home/user/sim_env
    cd /home/user/sim_env

    cat << 'EOF' > run_sim.sh
#!/bin/bash
SEED=$1
python3 -c "
import math, sys
seed = int(sys.argv[1])
freq = 2.5 + (seed * 0.01)
for i in range(1000):
    t = i * 0.1
    print(f'{t},{math.sin(2 * math.pi * freq * t)}')
" $SEED > /home/user/sim_env/output.csv
EOF
    chmod +x run_sim.sh

    cat << 'EOF' > find_peak.py
import sys, csv, numpy as np
times = []
amps = []
with open('/home/user/sim_env/output.csv', 'r') as f:
    reader = csv.reader(f)
    for row in reader:
        times.append(float(row[0]))
        amps.append(float(row[1]))

n = len(times)
dt = times[1] - times[0]
yf = np.fft.fft(amps)
xf = np.fft.fftfreq(n, dt)
idx = np.argmax(np.abs(yf[1:n//2])) + 1
print(f"{xf[idx]:.3f}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
