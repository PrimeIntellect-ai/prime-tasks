#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shutil
import struct
import subprocess
import tempfile
import time
import wave

import numpy as np

PORT_DIR = "/app/c_port"
EXECUTABLE = os.path.join(PORT_DIR, "ste_processor")


def test_makefile_builds_native_executable():
    """Force a fresh Makefile build and verify that it produces a native executable."""
    assert os.path.isfile(os.path.join(PORT_DIR, "Makefile")), "Makefile is missing."
    assert os.path.isfile(os.path.join(PORT_DIR, "main.c")), "main.c is missing."
    assert os.path.isfile(os.path.join(PORT_DIR, "ste.c")), "ste.c is missing."

    for name in ("ste_processor", "main.o", "ste.o"):
        path = os.path.join(PORT_DIR, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    started = time.time()
    result = subprocess.run(
        ["make", "-B"], cwd=PORT_DIR, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE), "make did not create /app/c_port/ste_processor"
    assert os.path.getmtime(EXECUTABLE) >= started - 1, "make did not freshly build ste_processor"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "ste_processor must be a native ELF executable"


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    executable = "/app/c_port/ste_processor"
    assert os.path.isfile(executable), f"Executable {executable} not found. Did the Makefile run successfully?"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."


def test_mae_metric():
    """Run both the Python reference and the C program on the provided recording."""
    executable = "/app/c_port/ste_processor"
    py_script = "/app/processor.py"
    wav_file = "/app/recording.wav"
    py_out = "/tmp/py_out.txt"
    c_out = "/tmp/c_out.txt"

    py_cmd = ["python3", py_script, wav_file, py_out]
    result_py = subprocess.run(py_cmd, capture_output=True, text=True)
    assert result_py.returncode == 0, f"Python script failed to run: {result_py.stderr}"

    c_cmd = [executable, wav_file, c_out]
    result_c = subprocess.run(c_cmd, capture_output=True, text=True)
    assert result_c.returncode == 0, f"C program failed to run: {result_c.stderr}"

    assert os.path.isfile(py_out), "Python output file was not generated."
    assert os.path.isfile(c_out), "C output file was not generated."

    with open(py_out, "r") as f:
        ref = np.array([float(line.strip()) for line in f if line.strip()])
    with open(c_out, "r") as f:
        test = np.array([float(line.strip()) for line in f if line.strip()])

    assert len(ref) == len(test), f"Length mismatch between outputs: Python={len(ref)}, C={len(test)}"
    mae = np.mean(np.abs(ref - test))
    threshold = 0.001
    assert mae <= threshold, f"MAE {mae:.6f} exceeds the allowed threshold of {threshold}. The C logic does not match the Python reference closely enough."


def copy_runtime_libraries(executable, root):
    result = subprocess.run(["ldd", executable], capture_output=True, text=True, timeout=20)
    combined = result.stdout + result.stderr
    if result.returncode != 0 and "not a dynamic executable" not in combined:
        raise AssertionError(f"Unable to inspect executable dependencies: {combined}")

    libraries = set()
    for line in result.stdout.splitlines():
        line = line.strip()
        if "=>" in line:
            candidate = line.split("=>", 1)[1].strip().split()[0]
        else:
            candidate = line.split()[0] if line else ""
        if candidate.startswith("/"):
            libraries.add(candidate)

    for source in libraries:
        assert os.path.isfile(source), f"Missing runtime library reported by ldd: {source}"
        destination = os.path.join(root, source.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)


def run_isolated(wav_path):
    """Run the ELF in a minimal chroot with no Python, reference script, or prior outputs."""
    with tempfile.TemporaryDirectory(prefix="ste_chroot_") as root:
        shutil.copy2(EXECUTABLE, os.path.join(root, "ste_processor"))
        shutil.copy2(wav_path, os.path.join(root, "input.wav"))
        copy_runtime_libraries(EXECUTABLE, root)

        result = subprocess.run(
            ["chroot", root, "/ste_processor", "/input.wav", "/output.txt"],
            capture_output=True,
            text=True,
            timeout=20,
            env={"PATH": ""},
        )
        assert result.returncode == 0, f"Isolated C execution failed: {result.stderr}"
        output = os.path.join(root, "output.txt")
        assert os.path.isfile(output), "C program did not create its requested output file"
        with open(output, "r") as f:
            values = [float(line.strip()) for line in f if line.strip()]
        assert all(math.isfinite(value) for value in values), "Output contains non-finite values"
        return values


def expected_values(samples):
    values = []
    for offset in range(0, len(samples), 256):
        window = samples[offset:offset + 256]
        if len(window) < 256:
            break
        energy = sum(sample * sample for sample in window)
        values.append(0.0 if energy > 100000000.0 else float(energy))
    return values


def test_generated_inputs_without_reference_or_temp_oracle():
    """Exercise independent, unpredictable WAV inputs without exposing an oracle file."""
    rng = random.SystemRandom()
    cases = []

    # Include quiet, threshold-exceeding, zero, and partial trailing frames.
    samples_a = [rng.randint(-400, 400) for _ in range(256)]
    samples_a += [rng.randint(-30000, 30000) for _ in range(256)]
    samples_a += [0] * 256
    samples_a += [rng.randint(-700, 700) for _ in range(256)]
    samples_a += [rng.randint(-32768, 32767) for _ in range(rng.randint(1, 255))]
    cases.append(samples_a)

    samples_b = []
    for _ in range(6):
        limit = rng.choice([50, 250, 900, 12000, 32767])
        samples_b.extend(rng.randint(-limit, limit) for _ in range(256))
    samples_b += [rng.randint(-1000, 1000) for _ in range(73)]
    cases.append(samples_b)

    for samples in cases:
        fd, wav_path = tempfile.mkstemp(prefix="generated_", suffix=".wav")
        os.close(fd)
        try:
            with wave.open(wav_path, "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(rng.choice([8000, 16000, 22050, 44100]))
                wav_file.writeframes(struct.pack(f"<{len(samples)}h", *samples))

            expected = expected_values(samples)
            actual = run_isolated(wav_path)
            assert len(actual) == len(expected), f"Length mismatch: expected {len(expected)}, got {len(actual)}"
            mae = float(np.mean(np.abs(np.array(expected) - np.array(actual)))) if expected else 0.0
            assert mae <= 0.001, f"Generated-input MAE {mae:.6f} exceeds 0.001"
        finally:
            os.unlink(wav_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
