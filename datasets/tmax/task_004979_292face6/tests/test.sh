#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import os
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import scipy.io.wavfile as wav


def test_cext_energy_is_native_and_correct():
    import cext_energy

    module_path = Path(cext_energy.__file__).resolve()
    repo_path = Path("/home/user/audio_pipeline").resolve()

    assert module_path.parent == repo_path, (
        f"cext_energy was not built in place in {repo_path}: {module_path}"
    )
    assert any(str(module_path).endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"cext_energy is not a compiled extension module: {module_path}"
    )
    assert isinstance(cext_energy.__spec__.loader, importlib.machinery.ExtensionFileLoader), (
        "cext_energy was not loaded as a native extension module"
    )

    # Exercise the native function on verifier-generated int16 data. Extreme
    # values guarantee that a signed 32-bit accumulator would overflow.
    window_size = 4096
    rng = np.random.default_rng()
    samples = rng.integers(-32768, 32768, size=2 * window_size + 13, dtype=np.int16)
    samples[:window_size:2] = np.int16(-32768)
    samples[1:window_size:2] = np.int16(32767)

    actual = np.asarray(cext_energy.compute_energy(samples, window_size))
    complete = samples[:2 * window_size].astype(np.int64).reshape(2, window_size)
    expected = np.sum(complete * complete, axis=1, dtype=np.int64).astype(np.float64)

    assert actual.shape == expected.shape
    assert np.array_equal(actual, expected), (
        f"Native extension returned {actual!r}; expected {expected!r}"
    )


def test_output_energies_csv():
    output_path = "/home/user/output_energies.csv"
    audio_path = "/app/audio_data.wav"

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.exists(audio_path), f"Audio file {audio_path} does not exist."

    try:
        df = pd.read_csv(output_path, header=None)
        pred = df.values.flatten()
    except Exception as e:
        pytest.fail(f"Failed to read {output_path}: {e}")

    try:
        sr, data = wav.read(audio_path)
    except Exception as e:
        pytest.fail(f"Failed to read {audio_path}: {e}")

    window_size = 4096
    num_windows = len(data) // window_size
    ref = np.zeros(num_windows)
    for i in range(num_windows):
        window = data[i * window_size:(i + 1) * window_size].astype(np.float64)
        ref[i] = np.sum(window * window)

    assert len(pred) == len(ref), f"Expected {len(ref)} windows, but got {len(pred)}."

    mse = np.mean((pred - ref) ** 2)
    threshold = 0.001
    assert mse <= threshold, (
        f"MSE is {mse}, which is greater than the threshold {threshold}. "
        "The C extension logic is likely incorrect (e.g., integer overflow)."
    )
TEST_EOF

if cd /home/user/audio_pipeline \
   && python setup.py build_ext --inplace \
   && rm -f /home/user/output_energies.csv \
   && python process.py /app/audio_data.wav 4096 /home/user/output_energies.csv \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
