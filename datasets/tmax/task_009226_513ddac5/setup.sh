#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

python3 -c '
import random
with open("/home/user/sim_runs.log", "w") as f:
    for i in range(1000):
        if i == 742:
            f.write(f"RunID: RUN_742, FinalTemp: 45.2, MeanEnergy: 8432.1, Status: SUCCESS\n")
        else:
            energy = random.uniform(10.0, 20.0)
            f.write(f"RunID: RUN_{i}, FinalTemp: 45.2, MeanEnergy: {energy:.1f}, Status: SUCCESS\n")
'

cat << 'EOF' > /home/user/simulation.py
import json
import sys

def run_diffusion(grid_size):
    grid = [0.0] * grid_size
    grid[grid_size//2] = 100.0
    new_grid = grid[:]
    alpha = 0.1

    # Bug 1: Off-by-one boundary condition (will throw IndexError at len(grid))
    for i in range(1, len(grid)):
        new_grid[i] = grid[i] + alpha * (grid[i-1] - 2*grid[i] + grid[i+1])

    return new_grid

def find_equilibrium(init_val):
    val = init_val
    # Bug 2: Convergence failure (wrong sign on gradient update)
    for _ in range(1000):
        grad = 2 * (val - 50.0)
        val = val + 0.1 * grad # Should be val - 0.1 * grad
    return val

if __name__ == "__main__":
    if "--run-all" in sys.argv:
        try:
            diff_res = run_diffusion(11)
            eq_res = find_equilibrium(10.0)

            with open("/home/user/success.json", "w") as f:
                json.dump({
                    "diffusion_center": diff_res[11//2], 
                    "equilibrium": round(eq_res, 2)
                }, f)
            print("Successfully completed simulation runs.")
        except Exception as e:
            print(f"Failed to run simulation: {type(e).__name__}: {e}")
            sys.exit(1)
EOF

chmod -R 777 /home/user
