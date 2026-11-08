#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import wave
import struct
import subprocess
import numpy as np
import pytest

INPUT_PATH = '/app/audio/input.wav'
OUTPUT_PATH = '/home/user/output.wav'
PROCESSOR_PATH = '/home/user/processor'
MSE_THRESHOLD = 1.0


def compute_ground_truth(input_path):
    with wave.open(input_path, 'rb') as f:
        frames = f.readframes(f.getnframes())
        input_data = struct.unpack(f'<{f.getnframes()}h', frames)

    input_data = np.array(input_data, dtype=np.float32)
    output_data = np.zeros_like(input_data)
    taps = np.array([0.11, 0.22, 0.33, 0.15, -0.05, -0.12, -0.20, -0.04], dtype=np.float32)
    block_size = 1000

    for start in range(0, len(input_data), block_size):
        end = min(start + block_size, len(input_data))
        block = input_data[start:end]
        n = len(block)
        if n <= 0:
            continue

        mean = np.mean(block, dtype=np.float32)
        variance = np.var(block, dtype=np.float32)
        stddev = np.sqrt(max(0.0001, variance), dtype=np.float32)
        norm_buffer = (block - mean) / stddev

        out_block = np.zeros(n, dtype=np.float32)
        for i in range(n):
            out_val = np.float32(0.0)
            for j in range(8):
                if i - j >= 0:
                    out_val += norm_buffer[i - j] * taps[j]
            out_block[i] = out_val

        final_block = (out_block * stddev) + mean
        final_block = np.clip(final_block, -32768.0, 32767.0)
        output_data[start:end] = final_block.astype(np.int16)

    return output_data


def read_output(path):
    assert os.path.exists(path), f'Output file {path} does not exist.'
    try:
        with wave.open(path, 'rb') as f:
            assert f.getnchannels() == 1, 'Output must be mono.'
            assert f.getsampwidth() == 2, 'Output must use 16-bit PCM samples.'
            assert f.getframerate() == 16000, 'Output sample rate must be 16000 Hz.'
            frames = f.readframes(f.getnframes())
            data = struct.unpack(f'<{f.getnframes()}h', frames)
            return np.array(data, dtype=np.float32)
    except Exception as e:
        pytest.fail(f'Failed to read {path} as a valid WAV file: {e}')


def assert_matches(path, truth_data):
    agent_data = read_output(path)
    assert len(agent_data) == len(truth_data), (
        f'Output length mismatch: expected {len(truth_data)}, got {len(agent_data)}'
    )
    mse = np.mean((agent_data - truth_data) ** 2)
    # Integer PCM may differ by a sample value at rounding boundaries when a
    # valid Welford, two-pass, float, or double implementation is used.
    assert mse <= MSE_THRESHOLD, (
        f'MSE {mse} exceeds threshold {MSE_THRESHOLD}. The audio output is not correct.'
    )


def test_output_wav_mse_and_processor():
    truth_data = compute_ground_truth(INPUT_PATH).astype(np.float32)

    # Preserve the required check of the submitted final output.
    assert_matches(OUTPUT_PATH, truth_data)

    # Also execute the compiled artifact required by the instruction.
    assert os.path.isfile(PROCESSOR_PATH), 'Compiled processor does not exist.'
    assert os.access(PROCESSOR_PATH, os.X_OK), 'Compiled processor is not executable.'
    generated_path = '/tmp/verifier_output.wav'
    if os.path.exists(generated_path):
        os.remove(generated_path)
    result = subprocess.run(
        [PROCESSOR_PATH, INPUT_PATH, generated_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f'Processor exited with status {result.returncode}: '
        f'{result.stderr.decode(errors="replace")}'
    )
    assert_matches(generated_path, truth_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
