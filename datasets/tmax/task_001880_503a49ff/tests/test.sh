#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import sys

import numpy as np
import pytest
import soundfile as sf
from scipy.io import wavfile
from scipy.signal import butter, filtfilt

SCRIPT = "/home/user/fix_audio.py"
OUTPUT = "/home/user/clean.wav"
ORIGINAL = "/app/suspicious.wav"


@pytest.fixture(scope="session", autouse=True)
def execute_agent_script():
    """Require the submitted script itself to generate a fresh output file."""
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"The path {SCRIPT} is not a file."

    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            shutil.rmtree(OUTPUT)
        else:
            os.unlink(OUTPUT)

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT} did not finish within 60 seconds.")

    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_clean_wav_exists():
    """Test that the agent generated the clean.wav file."""
    output_wav = OUTPUT
    assert os.path.exists(output_wav), f"The output file {output_wav} does not exist."
    assert os.path.isfile(output_wav), f"The path {output_wav} is not a file."


def test_mse_threshold():
    """Test that the complete agent WAV matches the defined reference filter."""
    agent_wav = OUTPUT
    original_wav = ORIGINAL

    assert os.path.exists(agent_wav), f"Agent output {agent_wav} is missing."
    assert os.path.exists(original_wav), f"Original audio {original_wav} is missing."

    try:
        rate, data = wavfile.read(original_wav)
    except Exception as e:
        assert False, f"Failed to read {original_wav}: {e}"

    if data.ndim > 1:
        data = data.mean(axis=1)

    nyq = 0.5 * rate
    normal_cutoff = 4000 / nyq
    b, a = butter(5, normal_cutoff, btype="low", analog=False)
    reference_data = filtfilt(b, a, data)

    max_val = np.max(np.abs(reference_data))
    if max_val > 0:
        reference_data = np.int16(reference_data / max_val * 32767)
    else:
        reference_data = np.int16(reference_data)

    try:
        agent_rate, agent_data = wavfile.read(agent_wav)
    except Exception as e:
        assert False, f"Failed to read {agent_wav}: {e}"

    try:
        info = sf.info(agent_wav)
    except Exception as e:
        assert False, f"Failed to inspect {agent_wav}: {e}"

    assert info.format == "WAV", f"Output format is {info.format}, not WAV."
    assert info.subtype == "PCM_16", f"Output subtype is {info.subtype}, not 16-bit PCM."
    assert agent_data.dtype == np.int16, f"Output dtype is {agent_data.dtype}, not int16."
    assert agent_rate == rate, f"Output sample rate {agent_rate} does not match input rate {rate}."
    assert agent_data.ndim == 1, "Output channel layout does not match the mono input."
    assert len(agent_data) == len(reference_data), (
        f"Output has {len(agent_data)} samples; expected {len(reference_data)}."
    )

    min_len = min(len(reference_data), len(agent_data))
    assert min_len > 0, "Audio data is empty."

    mse = np.mean(
        (reference_data[:min_len].astype(np.float32)
         - agent_data[:min_len].astype(np.float32)) ** 2
    )

    threshold = 100.0
    assert mse <= threshold, (
        f"MSE is {mse:.4f}, which is greater than the threshold of {threshold}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
