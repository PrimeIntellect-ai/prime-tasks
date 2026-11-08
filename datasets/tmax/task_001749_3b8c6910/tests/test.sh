#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import secrets
import stat
import struct
import subprocess
import tempfile
import wave

import pytest

ORACLE_PATH = "/tests/oracle_processor.sh"
AGENT_PATH = "/home/user/fixed_processor.sh"
BINARY_PATH = "/app/bin/freq_extract"
NUM_FUZZ_TESTS = 50


def generate_random_wav(filename, duration, sample_rate, volume_multiplier):
    num_samples = int(duration * sample_rate)
    with wave.open(filename, "w") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        for _ in range(num_samples):
            val = int((random.random() * 2 - 1) * 32767 * volume_multiplier)
            val = max(-32768, min(32767, val))
            wav_file.writeframesraw(struct.pack("<h", val))


@pytest.fixture(scope="session", autouse=True)
def setup_seed():
    random.seed(42)


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent's script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent's script at {AGENT_PATH} is not executable"


def test_submission_is_not_reference_copy():
    with open(AGENT_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as reference:
        assert submitted.read() != reference.read(), "Submission must not be a byte-identical copy of the reference"


def test_exact_interface_and_safe_binary_invocation():
    token = secrets.token_hex(24)
    probe_log = os.path.join(tempfile.gettempdir(), f"freq_probe_{secrets.token_hex(12)}.jsonl")

    with tempfile.TemporaryDirectory() as temp_dir:
        wav_path = os.path.join(temp_dir, "input.wav")
        generate_random_wav(wav_path, 0.1, 8000, 0.5)
        digest = hashlib.sha256(open(wav_path, "rb").read()).hexdigest()
        expected_stdout = f"{token}:{digest}\n"

        backup_path = os.path.join(temp_dir, "freq_extract.backup")
        os.replace(BINARY_PATH, backup_path)
        try:
            probe = f'''#!/usr/bin/env python3
import hashlib
import json
import os
import sys
with open({probe_log!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
path = sys.argv[-1] if len(sys.argv) > 1 else ""
try:
    data = open(path, "rb").read()
except Exception:
    data = b""
print({token!r} + ":" + hashlib.sha256(data).hexdigest())
'''
            with open(BINARY_PATH, "w") as f:
                f.write(probe)
            os.chmod(BINARY_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                   stat.S_IRGRP | stat.S_IXGRP |
                                   stat.S_IROTH | stat.S_IXOTH)

            for bad_args in ([], [wav_path, wav_path]):
                if os.path.exists(probe_log):
                    os.unlink(probe_log)
                proc = subprocess.run(
                    [AGENT_PATH, *bad_args], capture_output=True, text=True, timeout=5
                )
                assert proc.returncode != 0, f"Script must reject {len(bad_args)} arguments"
                assert not os.path.exists(probe_log) or os.path.getsize(probe_log) == 0, \
                    "Script invoked freq_extract despite receiving an invalid argument count"

            if os.path.exists(probe_log):
                os.unlink(probe_log)
            proc = subprocess.run(
                [AGENT_PATH, wav_path], capture_output=True, text=True, timeout=5
            )
            assert proc.returncode == 0, f"Valid invocation failed: {proc.stderr}"
            assert proc.stdout == expected_stdout, "Script did not return freq_extract's exact output"
            assert "traceback" not in proc.stderr.lower(), "Script emitted traceback data"

            assert os.path.isfile(probe_log), "Script did not execute /app/bin/freq_extract"
            with open(probe_log) as f:
                calls = [json.loads(line) for line in f if line.strip()]
            assert calls == [["--safe-mode", wav_path]], \
                f"freq_extract must be called once with --safe-mode and the input path; got {calls!r}"
        finally:
            if os.path.lexists(BINARY_PATH):
                os.unlink(BINARY_PATH)
            os.replace(backup_path, BINARY_PATH)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle script missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle script at {ORACLE_PATH} is not executable"

    sample_rates = [8000, 16000, 22050, 44100, 48000]
    with tempfile.TemporaryDirectory() as temp_dir:
        for i in range(NUM_FUZZ_TESTS):
            duration = random.uniform(1.0, 10.0)
            sample_rate = random.choice(sample_rates)
            volume_multiplier = random.uniform(0.1, 1.0)
            wav_path = os.path.join(temp_dir, f"fuzz_{i}.wav")
            generate_random_wav(wav_path, duration, sample_rate, volume_multiplier)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, wav_path], capture_output=True, text=True, timeout=5
            )
            agent_proc = subprocess.run(
                [AGENT_PATH, wav_path], capture_output=True, text=True, timeout=5
            )

            assert agent_proc.returncode == oracle_proc.returncode, \
                f"Agent exit code ({agent_proc.returncode}) differs from oracle ({oracle_proc.returncode}) on input {wav_path}"
            assert agent_proc.stdout == oracle_proc.stdout, \
                f"Agent output differs from oracle on input {wav_path}.\n\nOracle output:\n{oracle_proc.stdout}\n\nAgent output:\n{agent_proc.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
