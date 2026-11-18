#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

SOURCE_DIR = "/home/user/synth_data"
MAIN_PATH = os.path.join(SOURCE_DIR, "main.go")
MODULE_PATH = os.path.join(SOURCE_DIR, "go.mod")
MOLECULE_PATH = "/home/user/molecule.txt"
PEAK_PATH = "/home/user/peak.txt"
BINARY_PATH = "/tmp/synth_data_verifier_bin"
STEPS = 1024
DT = 0.01


def reference_peak(masses, springs):
    n = len(masses)
    x = [1.0] + [0.0] * (n - 1)
    v = [0.0] * n
    signal = []

    for _ in range(STEPS):
        acceleration = []
        for i in range(n):
            force = sum(springs[i][j] * (x[j] - x[i]) for j in range(n))
            acceleration.append(force / masses[i])
        for i in range(n):
            v[i] += acceleration[i] * DT
        for i in range(n):
            x[i] += v[i] * DT
        signal.append(x[0])

    best_bin = None
    best_magnitude = -1.0
    for k in range(1, STEPS // 2 + 1):
        real = 0.0
        imag = 0.0
        for t, value in enumerate(signal):
            angle = 2.0 * math.pi * k * t / STEPS
            real += value * math.cos(angle)
            imag -= value * math.sin(angle)
        magnitude = math.hypot(real, imag)
        if magnitude > best_magnitude:
            best_magnitude = magnitude
            best_bin = k

    return f"{best_bin / (STEPS * DT):.4f}"


def run_case(config_text, masses, springs):
    with open(MOLECULE_PATH, "w") as f:
        f.write(config_text)

    if os.path.exists(PEAK_PATH):
        os.remove(PEAK_PATH)

    result = subprocess.run(
        [BINARY_PATH], cwd=SOURCE_DIR, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(PEAK_PATH), (
        f"File {PEAK_PATH} does not exist after executing the Go program."
    )

    with open(PEAK_PATH, "r") as f:
        raw = f.read()
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", raw), (
        f"{PEAK_PATH} must contain only one frequency formatted to four decimal places; got {raw!r}."
    )

    expected = reference_peak(masses, springs)
    assert raw.strip() == expected, (
        f"Expected dominant frequency {expected}, but got {raw.strip()!r}."
    )


def test_go_main_exists():
    assert os.path.isfile(MAIN_PATH), f"Go source file {MAIN_PATH} does not exist."
    assert os.path.isfile(MODULE_PATH), f"Go module file {MODULE_PATH} does not exist."

    result = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, "."],
        cwd=SOURCE_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"The Go program does not build. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(BINARY_PATH), "Building main.go did not produce an executable."


def test_peak_txt_exists_and_content():
    with open(MOLECULE_PATH, "r") as f:
        original_config = f.read()

    original_masses = [1.0, 1.0, 1.0]
    original_springs = [
        [0.0, 100.0, 0.0],
        [100.0, 0.0, 100.0],
        [0.0, 100.0, 0.0],
    ]
    assert reference_peak(original_masses, original_springs) == "1.5625"

    # Use a runtime-generated valid system to ensure peak.txt is produced by
    # parsing and simulating the supplied molecule rather than hardcoding the
    # answer for the image's initial input.
    m0 = 0.8 + 0.1 * secrets.randbelow(8)
    m1 = 0.8 + 0.1 * secrets.randbelow(8)
    target_bin = 12 + secrets.randbelow(19)
    target_hz = (target_bin + 0.17) / (STEPS * DT)
    spring = (2.0 * math.pi * target_hz) ** 2 / (1.0 / m0 + 1.0 / m1)
    random_config = (
        f"{m0:.12g} {m1:.12g}\n"
        f"0 {spring:.12g}\n"
        f"{spring:.12g} 0\n"
    )
    random_masses = [m0, m1]
    random_springs = [[0.0, spring], [spring, 0.0]]

    try:
        run_case(random_config, random_masses, random_springs)
        # Run the shipped configuration last so the final peak.txt is the
        # requested output for /home/user/molecule.txt.
        run_case(original_config, original_masses, original_springs)
    finally:
        with open(MOLECULE_PATH, "w") as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
