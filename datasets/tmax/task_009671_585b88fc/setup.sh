#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim /home/user/data

    cat << 'EOF' > /home/user/sim/spectro_mc.py
import multiprocessing
import numpy as np
import math

def simulate_chunk(seed):
    np.random.seed(seed)
    # Simulate photon energies in keV
    return np.random.lognormal(mean=1.5, sigma=0.8, size=5000).tolist()

def run_simulation():
    seeds = list(range(42, 142)) # 100 chunks
    pool = multiprocessing.Pool(processes=4)

    total_energy = 0.0
    all_energies = []

    # BUG: imap_unordered causes non-deterministic floating point addition order
    for result in pool.imap_unordered(simulate_chunk, seeds):
        all_energies.extend(result)
        total_energy += sum(result)

    pool.close()
    pool.join()

    return total_energy, all_energies

if __name__ == "__main__":
    e, _ = run_simulation()
    print(f"Total Energy: {e}")
EOF

    python3 -c "
import numpy as np
np.random.seed(999)
obs = np.random.lognormal(mean=1.48, sigma=0.82, size=250000)
with open('/home/user/data/obs_raw.csv', 'w') as f:
    f.write('timestamp,detector_id,energy_kev\n')
    for i, val in enumerate(obs):
        f.write(f'1600000000,{i%10},{val:.6f}\n')
"

    chown -R user:user /home/user/sim /home/user/data
    chmod -R 777 /home/user
