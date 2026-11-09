#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo libhdf5-dev espeak ffmpeg
    pip3 install pytest h5py numpy

    mkdir -p /app/sim_corpus/clean
    mkdir -p /app/sim_corpus/evil

    # Generate the audio file
    espeak -w /app/hydrophone_metadata.wav "The calibration run is successful. Please ensure all valid simulations have a peak amplitude strictly less than eighty five point five."

    # Generate the HDF5 corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import h5py
import numpy as np

def make_clean(path, idx):
    with h5py.File(f"{path}/clean_0{idx}.h5", "w") as f:
        f.create_dataset("/observational/metadata", data=np.array([1, 2, 3]))
        f.create_dataset("/mc_results/energy", data=np.array([1.0, 2.5, 3.1]))
        f.create_dataset("/mc_results/amplitude", data=np.array([80.0, 85.0, 84.9]))

for i in range(1, 6):
    make_clean("/app/sim_corpus/clean", i)

# Evil 1: Missing metadata
with h5py.File("/app/sim_corpus/evil/evil_01.h5", "w") as f:
    f.create_dataset("/mc_results/energy", data=np.array([1.0, 2.5, 3.1]))
    f.create_dataset("/mc_results/amplitude", data=np.array([80.0]))

# Evil 2: Negative energy
with h5py.File("/app/sim_corpus/evil/evil_02.h5", "w") as f:
    f.create_dataset("/observational/metadata", data=np.array([1, 2, 3]))
    f.create_dataset("/mc_results/energy", data=np.array([1.0, -0.5, 3.1]))
    f.create_dataset("/mc_results/amplitude", data=np.array([80.0]))

# Evil 3: Amplitude max >= 85.5
with h5py.File("/app/sim_corpus/evil/evil_03.h5", "w") as f:
    f.create_dataset("/observational/metadata", data=np.array([1, 2, 3]))
    f.create_dataset("/mc_results/energy", data=np.array([1.0, 2.5, 3.1]))
    f.create_dataset("/mc_results/amplitude", data=np.array([80.0, 85.5, 90.0]))

# Evil 4: Missing energy entirely
with h5py.File("/app/sim_corpus/evil/evil_04.h5", "w") as f:
    f.create_dataset("/observational/metadata", data=np.array([1, 2, 3]))
    f.create_dataset("/mc_results/amplitude", data=np.array([80.0]))
EOF

    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
