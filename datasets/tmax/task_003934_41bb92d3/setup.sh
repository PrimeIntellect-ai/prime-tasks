#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/logs', exist_ok=True)

alpha_logs = []
beta_logs = []
gamma_logs = []

# Normal transactions
def generate_noise(txid, start_ms):
    logs = []
    energy = 500
    state = [100, 200, 150, 50]

    ms = start_ms
    services = ['alpha', 'beta', 'gamma']
    for i in range(10):
        ms += random.randint(10, 50)
        svc = services[i % 3]
        # Valid state transformation keeping energy constant
        state[0] += 10
        state[1] -= 10
        time_str = f"2023-10-27T10:00:{ms//1000:02d}.{ms%1000:03d}Z"
        log_line = f"[{time_str}] [{txid}] [PROCESS] State:{','.join(map(str, state))}\n"
        if svc == 'alpha': alpha_logs.append(log_line)
        elif svc == 'beta': beta_logs.append(log_line)
        else: gamma_logs.append(log_line)

generate_noise("SIM-1111", 1000)
generate_noise("SIM-2222", 2000)

# The buggy transaction SIM-9942
ms = 5000
state = [300, -50, 100, 50] # Initial energy = 400
txid = "SIM-9942"

timeline = [
    ('alpha', 5010, [300, -50, 100, 50]),     # 400
    ('beta', 5035, [310, -60, 100, 50]),      # 400
    ('gamma', 5080, [290, -60, 120, 50]),     # 400
    ('alpha', 5112, [290, -60, 100, 70]),     # 400
    ('beta', 5150, [290, -60, 50, 120]),      # 400
    ('gamma', 5195, [300, -60, 40, 120]),     # 400
    ('alpha', 5233, [300, -60, 40, 120]),     # 400
    ('beta', 5281, [300, -60, 38, 120]),      # BUG! Energy = 398
    ('gamma', 5320, [310, -70, 38, 120]),     # 398
    ('alpha', 5366, [310, -70, 38, 120]),     # 398
]

for svc, time_ms, st in timeline:
    time_str = f"2023-10-27T10:00:{time_ms//1000:02d}.{time_ms%1000:03d}Z"
    log_line = f"[{time_str}] [{txid}] [PROCESS] State:{','.join(map(str, st))}\n"
    if svc == 'alpha': alpha_logs.append(log_line)
    elif svc == 'beta': beta_logs.append(log_line)
    else: gamma_logs.append(log_line)

generate_noise("SIM-3333", 6000)

with open('/home/user/logs/alpha.log', 'w') as f:
    f.writelines(alpha_logs)
with open('/home/user/logs/beta.log', 'w') as f:
    f.writelines(beta_logs)
with open('/home/user/logs/gamma.log', 'w') as f:
    f.writelines(gamma_logs)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
