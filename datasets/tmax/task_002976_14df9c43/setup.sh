#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest numpy matplotlib

    mkdir -p /app
    # Generate audio file directly using espeak to avoid pyttsx3 headless issues
    espeak -w /app/experiment_log.wav "The outlier threshold is exactly two point five standard deviations."

    # Create oracle script
    cat << 'EOF' > /app/oracle_pipeline.py
#!/usr/bin/env python3
import sys
import numpy as np

def process():
    lines = sys.stdin.read().strip().split('\n')
    if not lines or lines == ['']: return

    data = []
    for line in lines:
        row = [np.nan if x == '' else float(x) for x in line.split(',')]
        data.append(row)

    arr = np.array(data, dtype=np.float64)

    # 1. Impute
    col_means = np.nanmean(arr, axis=0)
    inds = np.where(np.isnan(arr))
    arr[inds] = np.take(col_means, inds[1])

    # 2. Clip (Z = 2.5)
    Z = 2.5
    m2 = np.mean(arr, axis=0)
    s2 = np.std(arr, axis=0, ddof=1)
    lower = m2 - Z * s2
    upper = m2 + Z * s2
    arr = np.clip(arr, lower, upper)

    # 3. Standardize
    m3 = np.mean(arr, axis=0)
    s3 = np.std(arr, axis=0, ddof=1)
    arr = (arr - m3) / s3

    # 4. Covariance
    cov = np.cov(arr, rowvar=False, ddof=1)

    # 5. Output
    cov_rounded = np.round(cov, 4)
    for row in cov_rounded:
        print(','.join([f"{val:.4f}" for val in row]))

if __name__ == "__main__":
    process()
EOF
    chmod +x /app/oracle_pipeline.py

    useradd -m -s /bin/bash user || true

    # Create buggy plot script
    cat << 'EOF' > /home/user/plot_cov.py
import matplotlib.pyplot as plt
import numpy as np

# Missing matplotlib.use("Agg") causes issues in some headless setups, 
# or the user explicitly calls plt.show() instead of plt.savefig()
data = np.eye(10)
plt.imshow(data)
plt.show() # Bug: hangs or fails in headless, doesn't save.
EOF

    chmod -R 777 /home/user
