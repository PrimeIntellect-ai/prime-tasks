#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip hdf5-tools gawk
    pip3 install pytest h5py numpy

    mkdir -p /home/user/data

    python3 -c "
import h5py
import numpy as np

np.random.seed(42)
obs = np.random.rand(100, 5)
obs[63] = [0.777, 0.777, 0.777, 0.777, 0.777]

mcmc = np.random.randn(100, 1000)
samples = np.random.randn(1000)
samples = samples - np.mean(samples) + 3.14159
mcmc[63] = samples

with h5py.File('/home/user/data/samples.h5', 'w') as f:
    f.create_dataset('observations', data=obs)
    f.create_dataset('mcmc_samples', data=mcmc)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
