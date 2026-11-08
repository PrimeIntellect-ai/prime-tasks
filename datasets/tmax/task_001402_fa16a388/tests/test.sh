#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

DATA_PATH = "/home/user/data.csv"
SOURCE_PATH = "/home/user/pipeline.c"
PIPELINE_PATH = "/home/user/pipeline"
TRACK_PATH = "/home/user/track.sh"
LOG_PATH = "/home/user/experiment.log"
EXPECTED_SEEDS = [10, 20, 30, 40, 50]
LINE_RE = re.compile(r"Seed: (-?\d+), Train_Mean: (-?\d+\.\d{4}), Test_Mean: (-?\d+\.\d{4})")
LIBC = ctypes.CDLL(None)
LIBC.srand.argtypes = [ctypes.c_uint]
LIBC.rand.argtypes = []
LIBC.rand.restype = ctypes.c_int


def read_data():
    with open(DATA_PATH, "r") as f:
        values = [float(line.strip()) for line in f if line.strip()]
    assert len(values) == 1000, f"Expected 1000 data values, found {len(values)}"
    return values


def expected_result(values, seed):
    LIBC.srand(seed)
    is_train = [(LIBC.rand() % 100) < 80 for _ in values]
    train = [value for value, selected in zip(values, is_train) if selected]
    test = [value for value, selected in zip(values, is_train) if not selected]
    assert train and test

    mean = sum(train) / len(train)
    variance = sum((value - mean) * (value - mean) for value in train) / len(train)
    stddev = math.sqrt(variance)
    assert stddev > 0

    train_mean = sum((value - mean) / stddev for value in train) / len(train)
    test_mean = sum((value - mean) / stddev for value in test) / len(test)
    return train_mean, test_mean


def verify_output_line(line, seed, values):
    match = LINE_RE.fullmatch(line.strip())
    assert match is not None, f"Output format incorrect: {line!r}"
    assert int(match.group(1)) == seed, f"Expected seed {seed}, got {match.group(1)}"

    displayed_train = match.group(2)
    assert displayed_train in ("0.0000", "-0.0000"), \
        f"Train_Mean is not zero after train-only standardization: {line}"

    expected_train, expected_test = expected_result(values, seed)
    actual_train = float(displayed_train)
    actual_test = float(match.group(3))
    assert abs(actual_train - expected_train) <= 0.000051
    assert abs(actual_test - expected_test) <= 0.000051, \
        f"Wrong Test_Mean for seed {seed}: expected {expected_test:.4f}, got {actual_test:.4f}"


def run_pipeline(path, seed, values):
    result = subprocess.run(
        [path, str(seed)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, \
        f"{path} failed for seed {seed}: {result.stderr}"
    lines = result.stdout.splitlines()
    assert len(lines) == 1, f"Expected exactly one output line, got: {result.stdout!r}"
    verify_output_line(lines[0], seed, values)


# Preserve the original verifier's assertions.
def test_track_sh_exists_and_executable():
    script_path = "/home/user/track.sh"
    assert os.path.isfile(script_path), f"File not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_experiment_log_exists():
    log_path = "/home/user/experiment.log"
    assert os.path.isfile(log_path), f"File not found: {log_path}"


def test_experiment_log_contents():
    assert os.path.isfile(LOG_PATH), f"File not found: {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected 5 lines in {LOG_PATH}, found {len(lines)}"
    expected_seeds = ["10", "20", "30", "40", "50"]
    for i, line in enumerate(lines):
        seed = expected_seeds[i]
        assert f"Seed: {seed}" in line, \
            f"Expected Seed: {seed} in line {i+1}, got: {line}"
        match = re.search(r"Train_Mean:\s*(-?0\.0000)", line)
        assert match is not None, \
            f"Train_Mean is not 0.0000 in line {i+1}: {line}. The data leakage bug might not be correctly fixed."
        match_test = re.search(r"Test_Mean:\s*(-?\d+\.\d{4})", line)
        assert match_test is not None, \
            f"Test_Mean format incorrect in line {i+1}: {line}"


def test_source_and_compiled_pipeline_are_real_and_correct():
    assert os.path.isfile(SOURCE_PATH), f"File not found: {SOURCE_PATH}"
    assert os.path.isfile(PIPELINE_PATH), f"File not found: {PIPELINE_PATH}"
    assert os.access(PIPELINE_PATH, os.X_OK), f"Pipeline is not executable: {PIPELINE_PATH}"
    with open(PIPELINE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline must be a compiled executable"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="pipeline-build-"), "pipeline")
    build = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", rebuilt, "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, f"pipeline.c does not compile: {build.stderr}"

    original_data = open(DATA_PATH, "rb").read()
    try:
        # Use verifier-generated data so hard-coded log values cannot satisfy the check.
        with open(DATA_PATH, "w") as f:
            for i in range(1000):
                value = ((i * 37) % 211) * 0.73 + math.sin(i * 0.17) * 9.0
                if i % 97 == 0:
                    value += 180.0
                f.write(f"{value:.8f}\n")
        values = read_data()
        for seed in (7, 10, 123, 999):
            run_pipeline(PIPELINE_PATH, seed, values)
            run_pipeline(rebuilt, seed, values)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)


def test_track_script_really_invokes_pipeline_and_populates_log():
    values = read_data()
    token = uuid.uuid4().hex
    marker = f"/tmp/pipeline-calls-{token}"
    backup = f"/tmp/pipeline-bin-{token}"
    shutil.copy2(PIPELINE_PATH, backup)

    wrapper = f'''#!/bin/bash
printf '%s\\n' "$*" >> "{marker}"
exec "{backup}" "$@"
'''
    try:
        with open(PIPELINE_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(PIPELINE_PATH, 0o755)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        result = subprocess.run(
            [TRACK_PATH], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert result.returncode == 0, f"track.sh failed: {result.stderr}"
        assert os.path.isfile(marker), "track.sh did not invoke /home/user/pipeline"
        with open(marker, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        assert calls == [str(seed) for seed in EXPECTED_SEEDS], \
            f"pipeline invocations were not the required seeds in order: {calls}"

        assert os.path.isfile(LOG_PATH), f"File not found after running track.sh: {LOG_PATH}"
        with open(LOG_PATH, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 5, f"Expected 5 logged lines, found {len(lines)}"
        for line, seed in zip(lines, EXPECTED_SEEDS):
            verify_output_line(line, seed, values)
    finally:
        shutil.copy2(backup, PIPELINE_PATH)
        os.chmod(PIPELINE_PATH, 0o755)
        for path in (backup, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
