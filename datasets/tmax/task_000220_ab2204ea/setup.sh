#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/spectroscopy_sim.py
#!/usr/bin/env python3
import argparse
import math

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seed', type=int, required=True)
    args = parser.parse_args()

    # Deterministic pseudo-random execution time simulating workload
    val = 150.0 + 50.0 * math.sin(args.seed * 12.34) + (args.seed % 13) * 2.5
    print(f"Time: {val:.2f} ms")

if __name__ == '__main__':
    main()
EOF
    chmod +x /home/user/spectroscopy_sim.py

    chmod -R 777 /home/user
