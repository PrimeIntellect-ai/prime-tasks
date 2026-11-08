#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import uuid

import pytest

VALIDATOR_SRC = "/home/user/validator.cpp"
VALIDATOR_BIN = "/home/user/validator"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SECRET_ID = "8426"


def run_validator(binary, path, *extra_args):
    try:
        return subprocess.run(
            [binary, path, *extra_args],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator {binary} timed out on {path}")


@pytest.fixture(scope="session")
def validator_bins():
    assert os.path.isfile(VALIDATOR_SRC), f"The C++ source {VALIDATOR_SRC} does not exist."

    build_dir = tempfile.mkdtemp(prefix="validator_build_")
    rebuilt = os.path.join(build_dir, "validator_rebuilt")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", VALIDATOR_SRC, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"validator.cpp does not compile as C++:\n{result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    return [VALIDATOR_BIN, rebuilt]


def test_validator_exists_and_executable():
    assert os.path.isfile(VALIDATOR_BIN), f"The binary {VALIDATOR_BIN} does not exist."
    assert os.access(VALIDATOR_BIN, os.X_OK), f"The binary {VALIDATOR_BIN} is not executable."
    with open(VALIDATOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{VALIDATOR_BIN} is not a compiled ELF executable."


def test_adversarial_corpus():
    # Preserve the original corpus assertions.
    if not (os.path.isfile(VALIDATOR_BIN) and os.access(VALIDATOR_BIN, os.X_OK)):
        pytest.fail(f"Validator binary {VALIDATOR_BIN} is missing or not executable.")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_clean = []
    for clean_file in clean_files:
        result = subprocess.run([VALIDATOR_BIN, clean_file], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(clean_file))

    failed_evil = []
    for evil_file in evil_files:
        result = subprocess.run([VALIDATOR_BIN, evil_file], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(evil_file))

    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(failed_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_dynamic_csv_validation(validator_bins):
    rng = random.SystemRandom()
    normal_uid = str(rng.randrange(1000, 10000))
    while normal_uid == SECRET_ID:
        normal_uid = str(rng.randrange(1000, 10000))

    ts1 = str(rng.randrange(1, 2_000_000_000))
    ts2 = str(rng.randrange(1, 2_000_000_000))
    bad_timestamp = ts1[:max(1, len(ts1) // 2)] + rng.choice(string.ascii_letters) + ts1[max(1, len(ts1) // 2):]
    bad_status = "BAD_" + uuid.uuid4().hex
    payload = uuid.uuid4().hex
    header = "event_id,timestamp,user_id,status,payload\n"

    cases = [
        (0, [
            f"-event,{ts1},{normal_uid},OK,{SECRET_ID}\n",
            f"abc,{ts2},{normal_uid},WARN,{payload}\n",
            f"3,0,{normal_uid},ERR,{bad_status}\n",
        ]),
        (1, [
            f"1,{ts1},{normal_uid},OK,{payload}\n",
            f"2,{ts2},{SECRET_ID},WARN,{payload}\n",
        ]),
        (1, [f"1,-{rng.randrange(1, 999999)},{normal_uid},OK,{payload}\n"]),
        (1, [f"1,{bad_timestamp},{normal_uid},ERR,{payload}\n"]),
        (1, [f"1,{ts1},{normal_uid},{bad_status},{payload}\n"]),
        (1, [
            f"1,{ts1},{normal_uid},OK,{payload}\n",
            f"2,{ts2},{normal_uid},{bad_status},{payload}\n",
            f"3,{ts1},{normal_uid},WARN,{payload}\n",
        ]),
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="csv_validation_") as directory:
        # Every case reuses the same unpredictable pathname, preventing a
        # classifier based on corpus directory or filename.
        csv_path = os.path.join(directory, uuid.uuid4().hex + ".csv")
        for expected, rows in cases:
            with open(csv_path, "w", encoding="utf-8", newline="") as f:
                f.write(header)
                f.writelines(rows)

            for binary in validator_bins:
                actual = run_validator(binary, csv_path)
                assert actual == expected, (
                    f"{binary} returned {actual}, expected {expected} for generated CSV:\n"
                    + header + "".join(rows)
                )


def test_requires_exactly_one_argument(validator_bins):
    with tempfile.TemporaryDirectory(prefix="validator_args_") as directory:
        csv_path = os.path.join(directory, "input.csv")
        with open(csv_path, "w", encoding="utf-8") as f:
            f.write("event_id,timestamp,user_id,status,payload\n")
            f.write("1,1,1001,OK,data\n")

        for binary in validator_bins:
            no_arg = subprocess.run([binary], capture_output=True, timeout=5)
            two_args = subprocess.run([binary, csv_path, csv_path], capture_output=True, timeout=5)
            assert no_arg.returncode != 0, f"{binary} accepted zero arguments"
            assert two_args.returncode != 0, f"{binary} accepted more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
