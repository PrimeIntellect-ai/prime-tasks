#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/protein.fasta
>Rhodopsin_fragment
MNGTEGPNFYVPFSNKTGVVRSPFEAPQYYLAEP
EOF

    cat << 'EOF' > /home/user/data/signal.csv
time,intensity
0.0,0.0
0.5,1.5
1.0,2.0
1.5,1.2
2.0,0.5
2.5,0.2
3.0,0.1
3.5,0.05
4.0,0.0
4.5,0.0
5.0,0.0
EOF

    cat << 'EOF' > /home/user/simulate.py
import csv
import math

def parse_fasta_length(filepath):
    # Bug: hardcoded length, agent needs to fix to read actual FASTA length
    # Note: actual length is 34. 34 * 0.12 = 4.08
    return 10 

def get_signal_interpolator(filepath):
    times = []
    intensities = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            times.append(float(row['time']))
            intensities.append(float(row['intensity']))

    def I(t):
        if t <= times[0]: return intensities[0]
        if t >= times[-1]: return intensities[-1]
        for i in range(len(times)-1):
            if times[i] <= t <= times[i+1]:
                dt = times[i+1] - times[i]
                w = (t - times[i]) / dt
                return intensities[i] * (1-w) + intensities[i+1] * w
        return 0.0
    return I

def adaptive_heun_step(f, t, y, h, tol=1e-4):
    k1 = f(t, y)
    y_euler = y + h * k1
    k2 = f(t + h, y_euler)
    y_heun = y + (h / 2.0) * (k1 + k2)

    err = abs(y_heun - y_euler) + 1e-15

    # INTENTIONAL BUG: Increases step size when error is large! Diverges.
    h_new = 0.9 * h * (err / tol)**0.5

    # Clamp h_new to avoid immediate crash in buggy version, but it still blows up
    h_new = max(1e-5, min(h_new, 0.5))

    if err <= tol:
        return t + h, y_heun, h_new, True
    else:
        return t, y, h_new, False

def run_simulation():
    L = parse_fasta_length('/home/user/data/protein.fasta')
    C = L * 0.12
    I = get_signal_interpolator('/home/user/data/signal.csv')

    def f(t, y):
        return -C * y + I(t)

    t = 0.0
    y = 0.0
    h = 0.1
    t_end = 5.0

    while t < t_end:
        if t + h > t_end:
            h = t_end - t
        t_next, y_next, h_next, success = adaptive_heun_step(f, t, y, h)
        if success:
            t = t_next
            y = y_next
        h = h_next

    print(f"Final y at t={t_end}: {y}")

if __name__ == "__main__":
    run_simulation()
EOF

    chmod -R 777 /home/user
