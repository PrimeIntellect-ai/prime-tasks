#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/data
    mkdir -p /app/bio_mcmc-1.2.3/bio_mcmc

    # Create dummy FASTA data
    cat << 'EOF' > /app/data/viral_sequences.fasta
>seq1
ACGT
>seq2
TGCA
>seq3
CGTA
>seq4
TACG
EOF

    # Create bio_mcmc package
    cat << 'EOF' > /app/bio_mcmc-1.2.3/setup.py
from setuptools import setup, find_packages

setup(
    name='bio_mcmc',
    version='1.2.3',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/bio_mcmc-1.2.3/bio_mcmc/__init__.py
from .sampler import Sampler
EOF

    cat << 'EOF' > /app/bio_mcmc-1.2.3/bio_mcmc/likelihood.py
import concurrent.futures
import math

class LikelihoodCalculator:
    def __init__(self, sequences):
        self.sequences = sequences

    def _chunk_loglik(self, chunk):
        # Dummy computation
        return -1.0

    def compute_total_loglik(self, param=1.0):
        chunks = [self.sequences[i:i+5] for i in range(0, len(self.sequences), 5)]
        total_loglik = 0.0
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = [executor.submit(self._chunk_loglik, chunk) for chunk in chunks]
            for future in concurrent.futures.as_completed(futures):
                total_loglik += future.result()
        return total_loglik
EOF

    cat << 'EOF' > /app/bio_mcmc-1.2.3/bio_mcmc/sampler.py
import random
import inspect
from .likelihood import LikelihoodCalculator

class Sampler:
    def __init__(self, sequences, seed=None):
        self.sequences = sequences
        self.seed = seed
        if seed is not None:
            random.seed(seed)

    def run(self, iterations):
        from . import likelihood
        src = inspect.getsource(likelihood.LikelihoodCalculator.compute_total_loglik)

        # If the non-deterministic as_completed is still present, return a slightly off value
        if "as_completed" in src:
            val = 0.0452918 + random.uniform(0.001, 0.01)
        else:
            val = 0.0452918

        return [val] * iterations
EOF

    # Install the vendored package
    pip3 install -e /app/bio_mcmc-1.2.3

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
