#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base r-cran-jsonlite
    pip3 install pytest numpy scipy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > reference.json
{"k2_threshold": 0.6}
EOF

    cat << 'EOF' > generate_data.py
import numpy as np

# True parameters for subject 42
k1_true = 0.35
k2_true = 0.75
A0 = 100.0

times = np.arange(0, 11, 1)
def B_exact(t, k1, k2):
    return (k1 * A0 / (k2 - k1)) * (np.exp(-k1 * t) - np.exp(-k2 * t))

B_true = B_exact(times, k1_true, k2_true)
# Add a tiny bit of noise
np.random.seed(123)
B_obs = B_true + np.random.normal(0, 0.5, len(times))

with open("raw_obs.txt", "w") as f:
    f.write("timestamp_string | time_hours | subject_id | B_concentration | status\n")
    for i, t in enumerate(times):
        f.write(f"2023-10-01T12:00:0{i}Z | {t} | 42 | {B_obs[i]:.4f} | OK\n")
        # Add some distractors
        f.write(f"2023-10-01T12:00:0{i}Z | {t} | 99 | {B_obs[i]*0.5:.4f} | OK\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
