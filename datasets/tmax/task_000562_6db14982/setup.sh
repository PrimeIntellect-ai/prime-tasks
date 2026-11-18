#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest mpi4py numpy

    mkdir -p /app/montecarlo-pi-mpi-1.0.0
    cat << 'EOF' > /app/montecarlo-pi-mpi-1.0.0/simulate.py
import argparse
import random
from mpi4py import MPI

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', type=int, required=True)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()

    # Assign base seed
    random.seed(args.seed + rank * 1000)

    # Distribute samples
    local_samples = args.samples // size
    local_inside = 0

    for _ in range(local_samples):
        x = random.random()
        y = random.random()
        if x*x + y*y <= 1.0:
            local_inside += 1

    # PERTURBATION: op=MPI.MAX instead of MPI.SUM
    total_inside = comm.reduce(local_inside, op=MPI.MAX, root=0)

    if rank == 0:
        pi_estimate = 4.0 * total_inside / args.samples
        print(f"Pi Estimate: {pi_estimate}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/montecarlo-pi-mpi-1.0.0/simulate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
