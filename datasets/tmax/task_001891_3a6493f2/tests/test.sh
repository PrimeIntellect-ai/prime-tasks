#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def get_secret_coeff():
    memdump_path = "/home/user/memdump.dat"
    if not os.path.exists(memdump_path):
        return None
    with open(memdump_path, "rb") as f:
        content = f.read()
    match = re.search(b"SECRET_COEFF=(\\d+)", content)
    if match:
        return int(match.group(1))
    return None


def get_valid_transactions():
    wal_path = "/home/user/data.wal"
    if not os.path.exists(wal_path):
        return []
    valid_txs = []
    with open(wal_path, "rb") as f:
        for line in f:
            try:
                decoded = line.decode('ascii').strip()
                match = re.match(r"^TX:(\d+)\s+VAL:(\d+)$", decoded)
                if match:
                    valid_txs.append((int(match.group(1)), int(match.group(2))))
            except UnicodeDecodeError:
                pass
    return valid_txs


def exercise_program(exe_path):
    rng = secrets.SystemRandom()
    coeff = rng.randint(2, 10000)
    multiple_of_17 = 17 * rng.randint(1, 10000)
    ordinary = rng.randint(1, 100000)
    while ordinary % 17 == 0:
        ordinary = rng.randint(1, 100000)
    txs = [
        (rng.randint(10000, 99999), multiple_of_17),
        (rng.randint(100000, 199999), ordinary),
        (rng.randint(200000, 299999), 17),
    ]
    input_data = ''.join(f"TX:{tx} VAL:{val}\n" for tx, val in txs).encode('ascii')
    expected = ''.join(
        f"TX:{tx} RESULT:{val * coeff}\n" for tx, val in txs
    ).encode('ascii')

    try:
        result = subprocess.run(
            [exe_path, str(coeff)],
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{exe_path} timed out while processing test transactions")

    assert result.returncode == 0, (
        f"{exe_path} exited abnormally with status {result.returncode}; "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert result.stdout == expected, (
        f"{exe_path} produced incorrect output on generated transactions, "
        "including values divisible by 17."
    )


def test_clean_wal_exists_and_correct():
    clean_wal_path = "/home/user/clean.wal"
    assert os.path.isfile(clean_wal_path), f"File {clean_wal_path} does not exist."

    valid_txs = get_valid_transactions()
    expected_lines = [f"TX:{tx} VAL:{val}" for tx, val in valid_txs]

    with open(clean_wal_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The contents of clean.wal do not match the expected valid transactions."


def test_executable_exists():
    exe_path = "/home/user/process_math"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."
    exercise_program(exe_path)


def test_repaired_source_compiles_and_runs():
    source_path = "/home/user/process_math.c"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_path = os.path.join(tmpdir, "process_math_rebuilt")
        compilation = subprocess.run(
            ["gcc", source_path, "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert compilation.returncode == 0, (
            "The repaired process_math.c does not compile: "
            + compilation.stderr.decode(errors='replace')
        )
        exercise_program(rebuilt_path)


def test_recovered_results_correct():
    results_path = "/home/user/recovered_results.txt"
    assert os.path.isfile(results_path), f"File {results_path} does not exist."

    coeff = get_secret_coeff()
    assert coeff is not None, "Could not find SECRET_COEFF in memdump.dat (test environment issue)."

    valid_txs = get_valid_transactions()
    expected_results = [f"TX:{tx} RESULT:{val * coeff}" for tx, val in valid_txs]

    with open(results_path, "r") as f:
        actual_results = [line.strip() for line in f if line.strip()]

    assert actual_results == expected_results, "The contents of recovered_results.txt do not match the expected computed results."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
