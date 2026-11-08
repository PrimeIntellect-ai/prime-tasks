#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess

SOURCE = "/home/user/etl_covar.c"
EXECUTABLE = "/home/user/etl_covar"
DATA = "/home/user/sensor_data.bin"
RESULT = "/home/user/covariance_result.txt"
REBUILT = "/tmp/etl_covar_rebuilt"


def test_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(SOURCE), "C source file /home/user/etl_covar.c is missing."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF binary."


def test_result_file_exists():
    """Test that the covariance result file exists."""
    assert os.path.isfile(RESULT), "Result file /home/user/covariance_result.txt is missing."


def test_covariance_result_content():
    """Test that the covariance result for the supplied data is exactly correct."""
    with open(DATA, "rb") as f:
        raw = f.read()
    assert len(raw) == 1000 * 2 * 8, "sensor_data.bin has an unexpected size."
    values = struct.unpack("=2000d", raw)
    assert all(values[2 * i] == float(i + 1) and values[2 * i + 1] == float(2 * (i + 1)) for i in range(1000)), \
        "sensor_data.bin does not contain the supplied sensor series."

    with open(RESULT, "rb") as f:
        content = f.read()
    expected = b"166833.333333\n"
    assert content == expected, f"Incorrect covariance result. Expected {expected!r}, but got {content!r}."


def test_source_builds_and_uses_gsl_covariance():
    """Compile the submitted source and verify both binaries call GSL covariance."""
    build = subprocess.run(
        ["gcc", SOURCE, "-o", REBUILT, "-lgsl", "-lgslcblas", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Submitted C source does not compile with GSL:\n{build.stderr}"

    for path in (EXECUTABLE, REBUILT):
        symbols = subprocess.run(
            ["nm", "-D", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert symbols.returncode == 0, f"Could not inspect symbols in {path}: {symbols.stderr}"
        assert "gsl_stats_covariance" in symbols.stdout, \
            f"{path} does not reference gsl_stats_covariance."


def _write_dataset(pairs):
    with open(DATA, "wb") as f:
        for x, y in pairs:
            f.write(struct.pack("=dd", float(x), float(y)))


def _expected_for_symmetric_pairs(deviations):
    # Each (dx,dy) is followed by (-dx,-dy), so both means are exactly zero.
    numerator = 2 * sum(dx * dy for dx, dy in deviations)
    n = 2 * len(deviations)
    return f"{numerator / (n - 1):.6f}\n".encode("ascii")


def _run_and_check(program, expected):
    try:
        os.remove(RESULT)
    except FileNotFoundError:
        pass
    run = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert run.returncode == 0, \
        f"{program} failed on valid binary sensor data (exit {run.returncode}): {run.stderr.decode(errors='replace')}"
    assert os.path.isfile(RESULT), f"{program} did not create {RESULT}."
    with open(RESULT, "rb") as f:
        actual = f.read()
    assert actual == expected, f"{program} wrote {actual!r}; expected {expected!r}."


def test_executables_compute_covariance_on_unseen_data():
    """Run the submitted artifact and a fresh source build on verifier-generated inputs."""
    with open(DATA, "rb") as f:
        original_data = f.read()
    original_result = None
    if os.path.exists(RESULT):
        with open(RESULT, "rb") as f:
            original_result = f.read()

    rng = random.SystemRandom()
    try:
        for _ in range(2):
            deviations = []
            while len(deviations) < 25:
                dx = rng.randint(-5000, 5000)
                dy = rng.randint(-5000, 5000)
                if dx != 0 and dy != 0:
                    deviations.append((dx, dy))
            x0 = rng.randint(-10000, 10000)
            y0 = rng.randint(-10000, 10000)
            pairs = []
            for dx, dy in deviations:
                pairs.append((x0 + dx, y0 + dy))
                pairs.append((x0 - dx, y0 - dy))
            _write_dataset(pairs)
            expected = _expected_for_symmetric_pairs(deviations)
            _run_and_check(EXECUTABLE, expected)
            _run_and_check(REBUILT, expected)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_result is None:
            try:
                os.remove(RESULT)
            except FileNotFoundError:
                pass
        else:
            with open(RESULT, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
