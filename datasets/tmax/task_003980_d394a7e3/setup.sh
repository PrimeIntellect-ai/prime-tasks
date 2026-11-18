#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/reduce_sim.py
import numpy as np
from mpi4py import MPI
import sys

def main():
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()

    if len(sys.argv) < 2:
        seed = 42
    else:
        seed = int(sys.argv[1])

    N_TOTAL = 5000000

    # Generate data on root
    if rank == 0:
        np.random.seed(seed)
        # Generate numbers with extreme scale differences to cause precision loss when added
        data = np.random.randn(N_TOTAL).astype(np.float64) * 1e6
        data[::2] *= 1e-12
    else:
        data = None

    # Determine counts and displacements for Scatterv
    counts = [N_TOTAL // size + (1 if x < N_TOTAL % size else 0) for x in range(size)]
    displ = [sum(counts[:x]) for x in range(size)]

    local_data = np.zeros(counts[rank], dtype=np.float64)

    if rank == 0:
        comm.Scatterv([data, counts, displ, MPI.DOUBLE], local_data, root=0)
    else:
        comm.Scatterv([None, counts, displ, MPI.DOUBLE], local_data, root=0)

    # Local summation
    local_sum = np.sum(local_data)

    # Parallel reduction
    global_sum = comm.reduce(local_sum, op=MPI.SUM, root=0)

    if rank == 0:
        print(f"{global_sum:.12f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
