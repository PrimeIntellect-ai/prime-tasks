#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install packages needed for setup and agent
    apt-get install -y python3-h5py python3-numpy gcc build-essential libhdf5-dev

    # Create user
    useradd -m -s /bin/bash user || true

    # Create HDF5 file
    python3 -c "import h5py; import numpy as np; f = h5py.File('/home/user/ref.h5', 'w'); f.create_dataset('weights', data=np.array([1.5, 2.0, 0.5], dtype=np.float64)); f.close()"

    # Create FASTA file
    cat << 'EOF' > /home/user/data.fasta
>seq1
ACGT
ACGT
>seq2
ACGT
>seq3
ACGTACGT
ACGT
EOF

    # Set permissions
    chmod -R 777 /home/user
