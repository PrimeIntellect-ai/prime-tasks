#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/data/impressions.csv
date,variant,impressions
2023-10-01,A,500
2023-10-01,B,520
2023-10-02,A,500
2023-10-02,B,530
EOF

    cat << 'EOF' > /home/user/data/conversions.csv
date,variant,conversions
2023-10-01,A,25
2023-10-01,B,35
2023-10-02,A,25
2023-10-02,B,35
EOF

    cat << 'EOF' > /home/user/scripts/plot_results.py
import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import beta

# Aggregated data (hardcoded for the plot script)
conv_A, imp_A = 50, 1000
conv_B, imp_B = 70, 1050

x = np.linspace(0, 0.15, 1000)
y_A = beta.pdf(x, 1 + conv_A, 1 + imp_A - conv_A)
y_B = beta.pdf(x, 1 + conv_B, 1 + imp_B - conv_B)

plt.plot(x, y_A, label='Variant A')
plt.plot(x, y_B, label='Variant B')
plt.legend()

# BUG: plt.show() clears the canvas before savefig, or crashes in headless mode
plt.show()
plt.savefig('/home/user/posterior_plot.png')
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/scripts
    chmod -R 777 /home/user
