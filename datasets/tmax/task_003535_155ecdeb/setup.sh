#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy scipy

    mkdir -p /home/user/spectroscopy_ml

    cat << 'EOF' > /home/user/spectroscopy_ml/generate_spectra.py
import numpy as np
import random
from scipy.optimize import root_scalar

def nonlinear_response(I, source_val):
    # I^3 + 0.5*I - source_val = 0
    return I**3 + 0.5 * I - source_val

def simulate_chunk(start_idx, end_idx):
    # Domain definition
    x = np.linspace(0, 10, 100000)[start_idx:end_idx]
    # Source spectrum
    source = np.sin(x)**2 + 0.1 * x

    chunk_energy = 0.0
    for s in source:
        # Solve nonlinear equation for true intensity
        res = root_scalar(nonlinear_response, args=(s,), bracket=[0, 10])
        chunk_energy += res.root
    return chunk_energy

def main():
    # Domain decomposition
    chunk_size = 1000
    total_points = 100000

    chunks = []
    for i in range(0, total_points, chunk_size):
        chunks.append((i, i + chunk_size))

    # Simulate map-reduce with randomized return order
    random.seed(123)
    random.shuffle(chunks)

    energies = []
    for (start, end) in chunks:
        # deliberately generating float precision issues by mixing very large and very small chunks 
        # (though here just adding random order of same-sized chunks)
        energies.append(simulate_chunk(start, end))

    # FLOTING POINT REDUCTION ORDER ISSUE HERE
    # The standard sum will have roundoff errors depending on the random shuffle.
    total_energy = sum(energies)
    print(f"Total Integrated Energy: {total_energy}")

if __name__ == '__main__':
    main()
EOF

    python3 -c "
import numpy as np
np.random.seed(100)
true_mean = 15.2
noise = np.random.normal(0, 2.5, 500)
observations = true_mean + noise

with open('/home/user/spectroscopy_ml/observations.csv', 'w') as f:
    f.write('id,intensity\n')
    for i, val in enumerate(observations):
        f.write(f'{i},{val}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
