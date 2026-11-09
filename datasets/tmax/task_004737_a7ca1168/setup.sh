#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip hdf5-tools bc gawk
    pip3 install pytest numpy h5py

    mkdir -p /home/user

    cat << 'EOF' > /home/user/seqs.fasta
>seq1
ACGTACGTAC
>seq2
ACGTACGTACACGTACGTAC
>seq3
ACGTACGTACACGTACGTACACGTACGTAC
EOF

    python3 -c "
import h5py
import numpy as np
with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('/X', data=np.array([[1.0, 2.0, 0.0], [0.0, 1.0, 1.0], [1.0, 0.0, 1.0]], dtype=np.float64))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
