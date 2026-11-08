#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

import pytest

SOURCE_FILE = "/home/user/spectral_profiler.rs"
EXECUTABLE = "/home/user/spectral_profiler"
SIGNAL_FILE = "/home/user/data/signal.txt"
LOG_FILE = "/home/user/mesh_validation.log"

EXPECTED_ORIGINAL_LINES = [
    "Mesh 0: 18.0 - INVALID",
    "Mesh 1: 30.5 - INVALID",
    "Mesh 2: 43.0 - VALID",
    "Mesh 3: 55.5 - VALID",
]


def expected_lines_from_signal(path):
    with open(path, "r") as f:
        values = [float(line.strip()) for line in f if line.strip()]

    assert len(values) == 400, f"Expected 400 signal values, found {len(values)}"
    maxima = []
    for mesh in range(4):
        start = mesh * 25
        end = start + 25
        maxima.append(max(values[obs * 100 + col] for obs in range(4) for col in range(start, end)))

    return [
        f"Mesh {mesh}: {maximum:.1f} - {'VALID' if maximum > 40.0 else 'INVALID'}"
        for mesh, maximum in enumerate(maxima)
    ]


def run_and_check(program, expected):
    result = subprocess.run(
        [program],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}; stderr: {result.stderr!r}"
    )
    assert result.stdout.splitlines() == expected, (
        f"Unexpected stdout from {program}: expected {expected!r}, got {result.stdout.splitlines()!r}"
    )


@pytest.fixture(scope="session")
def freshly_compiled(tmp_path_factory):
    output = tmp_path_factory.mktemp("compiled") / "spectral_profiler"
    result = subprocess.run(
        ["rustc", "-O", SOURCE_FILE, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, f"Rust source failed to compile: {result.stderr}"
    return str(output)


def test_rust_source_exists():
    source_file = "/home/user/spectral_profiler.rs"
    assert os.path.isfile(source_file), f"Rust source file missing: {source_file}"


def test_executable_exists_and_runnable():
    executable = "/home/user/spectral_profiler"
    assert os.path.isfile(executable), f"Compiled executable missing: {executable}"

    st = os.stat(executable)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"File is not executable: {executable}"

    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable was not produced as a native compiled binary: {executable}"


def test_mesh_validation_log_content():
    log_file = "/home/user/mesh_validation.log"
    assert os.path.isfile(log_file), f"Log file missing: {log_file}"

    expected_lines = [
        "Mesh 0: 18.0 - INVALID",
        "Mesh 1: 30.5 - INVALID",
        "Mesh 2: 43.0 - VALID",
        "Mesh 3: 55.5 - VALID"
    ]

    with open(log_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_file}, found {len(actual_lines)}"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"


def test_programs_process_supplied_data(freshly_compiled):
    expected = expected_lines_from_signal(SIGNAL_FILE)
    assert expected == EXPECTED_ORIGINAL_LINES, "The supplied signal data no longer has the expected maxima"
    run_and_check(EXECUTABLE, expected)
    run_and_check(freshly_compiled, expected)


def test_programs_process_unseen_data(freshly_compiled):
    with open(SIGNAL_FILE, "rb") as f:
        original_data = f.read()

    rng = secrets.SystemRandom()
    target_choices = [31.7, 39.9, 40.0, 40.1, 47.3, 58.6, 72.4]
    targets = [rng.choice(target_choices) for _ in range(4)]
    values = []

    for obs in range(4):
        for col in range(100):
            mesh = col // 25
            delta = rng.randint(1, 300) / 10.0
            values.append(round(targets[mesh] - delta, 1))

    for mesh, target in enumerate(targets):
        obs = rng.randrange(4)
        col = mesh * 25 + rng.randrange(25)
        values[obs * 100 + col] = target

    generated_data = "".join(f"{value:.1f}\n" for value in values).encode()

    try:
        with open(SIGNAL_FILE, "wb") as f:
            f.write(generated_data)
        expected = expected_lines_from_signal(SIGNAL_FILE)
        run_and_check(EXECUTABLE, expected)

        with open(SIGNAL_FILE, "wb") as f:
            f.write(generated_data)
        run_and_check(freshly_compiled, expected)
    finally:
        with open(SIGNAL_FILE, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
