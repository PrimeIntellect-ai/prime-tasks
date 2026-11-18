#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analyze_signal.py
#!/usr/bin/env python3
import numpy as np
import time

def slow_density_estimation(data, x_grid, bandwidth=0.1):
    # This naive implementation is the bottleneck: O(N * M) in pure Python
    density = np.zeros(len(x_grid))
    for i, x in enumerate(x_grid):
        for d in data:
            density[i] += np.exp(-0.5 * ((x - d) / bandwidth)**2)
    return density / (len(data) * bandwidth * np.sqrt(2 * np.pi))

def main():
    np.random.seed(42)
    # Synthetic spectroscopy data: 3 overlapping peaks
    data = np.random.normal(loc=[2, 5, 8], scale=0.5, size=(1000, 3)).flatten()
    x_grid = np.linspace(0, 10, 1000)

    start = time.time()
    density = slow_density_estimation(data, x_grid, bandwidth=0.1)
    end = time.time()

    print(f"Density estimation took {end - start:.4f} seconds")

    # Optimization/peak finding
    peak_idx = np.argmax(density)
    best_x = x_grid[peak_idx]

    with open('/home/user/result.txt', 'w') as f:
        f.write(f"{best_x:.4f}\n")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/analyze_signal.py
    chmod -R 777 /home/user
