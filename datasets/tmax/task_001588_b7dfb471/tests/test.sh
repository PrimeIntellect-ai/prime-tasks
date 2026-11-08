#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np

def test_avg_spectrum():
    agent_file = '/home/user/avg_spectrum.npy'
    assert os.path.exists(agent_file), f"Agent output file not found at {agent_file}"

    # Load agent array
    try:
        agent_array = np.load(agent_file)
    except Exception as e:
        assert False, f"Failed to load agent array from {agent_file}: {e}"

    # Recompute golden array
    genome_file = '/app/genome.txt'
    assert os.path.exists(genome_file), f"Genome file missing: {genome_file}"

    with open(genome_file, 'r') as f:
        seq = f.read().strip()

    mapping = {'A': 1.5, 'C': -0.5, 'G': 0.5, 'T': -1.5}
    window_size = 1000
    num_windows = len(seq) // window_size

    spectra = []
    for i in range(num_windows):
        chunk = seq[i*window_size : (i+1)*window_size]
        numeric = np.array([mapping.get(c, 0.0) for c in chunk])
        fft_vals = np.fft.fft(numeric)
        power = np.abs(fft_vals)**2
        spectra.append(power)

    golden_array = np.mean(spectra, axis=0)

    # Check shape
    assert agent_array.shape == golden_array.shape, (
        f"Agent array shape {agent_array.shape} does not match expected shape {golden_array.shape}"
    )

    # Compute MSE
    mse = np.mean((golden_array - agent_array)**2)
    threshold = 1e-5
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
