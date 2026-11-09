#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest

AGENT_BINARY = "/home/user/filter_etl"
AGENT_SOURCE = "/home/user/filter_etl.c"
ORACLE_BINARY = "/app/etl_oracle"
CLEAN_CORPUS_DIR = "/verify/clean/"
EVIL_CORPUS_DIR = "/verify/evil/"


def run_program(program, *args):
    return subprocess.run(
        [program, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2,
    )


def test_binary_exists_and_executable():
    assert os.path.exists(AGENT_BINARY), f"The agent binary is missing at {AGENT_BINARY}"
    assert os.path.isfile(AGENT_BINARY), f"{AGENT_BINARY} is not a file"
    assert os.access(AGENT_BINARY, os.X_OK), f"The agent binary at {AGENT_BINARY} is not executable"
    with open(AGENT_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_BINARY} is not a compiled ELF executable"

    assert os.path.isfile(ORACLE_BINARY), f"Reference oracle missing at {ORACLE_BINARY}"
    with open(AGENT_BINARY, "rb") as submitted, open(ORACLE_BINARY, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submitted executable is byte-identical to the reference oracle"


def test_clean_corpus():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    if not files:
        pytest.fail(f"No files found in {CLEAN_CORPUS_DIR}")

    failed_files = []
    for f in files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, f)
        result = run_program(AGENT_BINARY, filepath)
        if result.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(files)} clean files rejected (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    if not files:
        pytest.fail(f"No files found in {EVIL_CORPUS_DIR}")

    failed_files = []
    for f in files:
        filepath = os.path.join(EVIL_CORPUS_DIR, f)
        result = run_program(AGENT_BINARY, filepath)
        if result.returncode == 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(files)} evil files bypassed (expected non-zero exit code). Offending files: {', '.join(failed_files)}")


@pytest.fixture(scope="session")
def rebuilt_binary():
    assert os.path.exists(AGENT_SOURCE), f"The required C source is missing at {AGENT_SOURCE}"
    assert os.path.isfile(AGENT_SOURCE), f"{AGENT_SOURCE} is not a file"
    assert os.path.getsize(AGENT_SOURCE) > 0, f"{AGENT_SOURCE} is empty"

    build_dir = tempfile.mkdtemp(prefix="source_build_")
    output = os.path.join(build_dir, "rebuilt_filter")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", AGENT_SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "C source did not compile:\n" + result.stderr.decode(errors="replace")
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    yield output
    shutil.rmtree(build_dir, ignore_errors=True)


def test_source_exists_and_compiles(rebuilt_binary):
    assert os.path.exists(rebuilt_binary)


def expected_clean(rows):
    for _, value in rows:
        if value < -1.0 or value > 1.0:
            return False
    for i in range(1, len(rows)):
        if rows[i][0] <= rows[i - 1][0]:
            return False
        if rows[i][0] - rows[i - 1][0] != 50:
            return False
    return True


def write_dataset(path, rows):
    with open(path, "w", encoding="ascii") as f:
        for timestamp, value in rows:
            f.write(f"{timestamp},{value}\n")


def make_generated_cases():
    rng = random.SystemRandom()
    cases = [
        [(0, -1.0)],
        [(0, 1.0)],
        [(-100, -1.0), (-50, 0.0), (0, 1.0)],
        [(10, 1.0001)],
        [(10, -1.0001)],
        [(10, 0.0), (60, 0.0), (60, 0.0)],
        [(10, 0.0), (61, 0.0)],
        [(10, 0.0), (59, 0.0)],
    ]

    clean_values = [-1.0, -0.9999, -0.5, 0.0, 0.5, 0.9999, 1.0]
    for _ in range(52):
        count = rng.randint(2, 18)
        start = rng.randint(-10**12, 10**12)
        rows = [(start + 50 * i, rng.choice(clean_values)) for i in range(count)]

        if rng.randrange(3) == 0:
            cases.append(rows)
            continue

        mode = rng.choice(["value_high", "value_low", "bad_gap", "duplicate", "reverse"])
        index = rng.randrange(count)
        if mode == "value_high":
            rows[index] = (rows[index][0], rng.choice([1.0001, 1.01, 2.0, 100.0]))
        elif mode == "value_low":
            rows[index] = (rows[index][0], rng.choice([-1.0001, -1.01, -2.0, -100.0]))
        else:
            index = rng.randrange(1, count)
            if mode == "bad_gap":
                offset = rng.choice([-101, -51, -1, 1, 49, 50, 101])
                rows[index:] = [(ts + offset, value) for ts, value in rows[index:]]
            elif mode == "duplicate":
                rows[index] = (rows[index - 1][0], rows[index][1])
            else:
                rows[index] = (rows[index - 1][0] - rng.randint(1, 100), rows[index][1])
        cases.append(rows)

    rng.shuffle(cases)
    return cases


def test_argument_count():
    assert run_program(AGENT_BINARY).returncode != 0, "Executable accepted zero arguments"
    sample = os.path.join(CLEAN_CORPUS_DIR, os.listdir(CLEAN_CORPUS_DIR)[0])
    assert run_program(AGENT_BINARY, sample, sample).returncode != 0, "Executable accepted more than one argument"


def test_fresh_randomized_datasets(rebuilt_binary):
    work_dir = tempfile.mkdtemp(prefix=secrets.token_hex(12) + "_")
    hidden_oracle = os.path.join(work_dir, secrets.token_hex(16))
    cases = make_generated_cases()

    try:
        paths = []
        for rows in cases:
            path = os.path.join(work_dir, secrets.token_hex(16) + ".csv")
            write_dataset(path, rows)
            paths.append((path, expected_clean(rows)))

        # The final implementation must work independently of the proprietary oracle.
        os.rename(ORACLE_BINARY, hidden_oracle)
        try:
            for program in (AGENT_BINARY, rebuilt_binary):
                for path, should_be_clean in paths:
                    result = run_program(program, path)
                    if should_be_clean:
                        assert result.returncode == 0, f"{program} rejected generated clean dataset {path}"
                    else:
                        assert result.returncode != 0, f"{program} accepted generated corrupted dataset {path}"
        finally:
            os.rename(hidden_oracle, ORACLE_BINARY)
    finally:
        if os.path.exists(hidden_oracle) and not os.path.exists(ORACLE_BINARY):
            os.rename(hidden_oracle, ORACLE_BINARY)
        shutil.rmtree(work_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
