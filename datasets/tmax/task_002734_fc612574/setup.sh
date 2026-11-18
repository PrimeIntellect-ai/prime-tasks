#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ libhdf5-dev hdf5-tools
    pip3 install pytest numpy h5py

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Create the legacy partitioner Python script
    cat << 'EOF' > /app/legacy.py
import sys
import h5py
import numpy as np
import time

def partition(coords, indices, depth, part_offset):
    if depth == 0:
        return [(indices, part_offset)]
    mins = np.min(coords, axis=0)
    maxs = np.max(coords, axis=0)
    axis = np.argmax(maxs - mins)
    median = np.median(coords[:, axis])
    left_mask = coords[:, axis] < median
    right_mask = ~left_mask
    if not np.any(left_mask) or not np.any(right_mask):
        mid = len(coords) // 2
        left_mask = np.arange(len(coords)) < mid
        right_mask = ~left_mask
    left_res = partition(coords[left_mask], indices[left_mask], depth - 1, part_offset)
    right_res = partition(coords[right_mask], indices[right_mask], depth - 1, part_offset + (1 << (depth - 1)))
    return left_res + right_res

def main():
    infile = sys.argv[1]
    outfile = sys.argv[2]
    time.sleep(2) # Artificial inefficiency
    with h5py.File(infile, 'r') as f:
        coords = f['/coordinates'][:]
    indices = np.arange(len(coords))
    leaves = partition(coords, indices, 4, 0)
    part_ids = np.zeros(len(coords), dtype=np.int32)
    for idx, pid in leaves:
        part_ids[idx] = pid
    with h5py.File(outfile, 'w') as f:
        f.create_dataset('/partition_ids', data=part_ids, dtype='i4')

if __name__ == '__main__':
    main()
EOF

    # Create the C wrapper to act as the stripped binary
    cat << 'EOF' > /app/wrapper.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char** argv) {
    char cmd[512];
    if (argc >= 3) {
        snprintf(cmd, sizeof(cmd), "python3 /app/legacy.py %s %s", argv[1], argv[2]);
    } else {
        snprintf(cmd, sizeof(cmd), "python3 /app/legacy.py /home/user/mesh_data.h5 /home/user/optimized_partitions.h5");
    }
    return system(cmd);
}
EOF

    gcc -O0 /app/wrapper.c -o /app/legacy_partitioner
    strip /app/legacy_partitioner
    chmod +x /app/legacy_partitioner

    # Generate initial mesh data
    cat << 'EOF' > /tmp/gen_mesh.py
import h5py
import numpy as np
np.random.seed(42)
data = np.random.rand(100000, 3).astype(np.float64)
with h5py.File('/home/user/mesh_data.h5', 'w') as f:
    f.create_dataset('/coordinates', data=data)
EOF
    python3 /tmp/gen_mesh.py

    chmod -R 777 /home/user
