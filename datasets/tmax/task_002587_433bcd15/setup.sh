#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/compute_energy.py
import numpy as np
import sys

def compute_energy(values, seed):
    if seed is not None:
        np.random.seed(seed)
    # Add simulation noise
    noise = np.random.randint(0, 10, size=values.shape, dtype=np.int32)
    v = values + noise

    # Compute sum of squares
    energy = np.sum(v * v)
    return energy

if __name__ == "__main__":
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else None
    data = np.loadtxt('/home/user/data.txt', dtype=np.int32)
    energy = compute_energy(data, seed)

    if energy < 0:
        print(f"Error: Negative energy calculated! ({energy})")
        sys.exit(1)
    print(f"Energy: {energy}")
EOF

    python3 -c "import numpy as np; data = np.full(10000, 463, dtype=np.int32); np.savetxt('/home/user/data.txt', data, fmt='%d')"

    chmod -R 777 /home/user
