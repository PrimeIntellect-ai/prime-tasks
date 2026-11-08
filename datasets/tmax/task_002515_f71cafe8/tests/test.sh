#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import random
import secrets
import subprocess
import tempfile

LOGS_PATH = "/home/user/logs.csv"
PERMS_PATH = "/home/user/perms.csv"
SOURCE_PATH = "/home/user/audit.c"
EXECUTABLE_PATH = "/home/user/audit"
VIOLATIONS_PATH = "/home/user/violations.txt"

ORIGINAL_LOGS = b"""U001,RES_A
U002,RES_B
U003,RES_C
U001,RES_C
U004,RES_D
U005,RES_E
"""
ORIGINAL_PERMS = b"""U001,RES_A,1
U002,RES_B,1
U003,RES_C,0
U001,RES_C,1
U004,RES_D,0
"""


def test_executable_exists():
    """Check that the compiled program /home/user/audit exists and is executable."""
    assert os.path.exists(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} does not exist. Did you compile the C program?"
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file."

    st = os.stat(EXECUTABLE_PATH)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"{EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled ELF executable."


def test_violations_file_exists():
    """Check that the violations.txt file was created."""
    assert os.path.exists(VIOLATIONS_PATH), f"{VIOLATIONS_PATH} does not exist. Did you run the program and save the output?"
    assert os.path.isfile(VIOLATIONS_PATH), f"{VIOLATIONS_PATH} is not a regular file."


def test_violations_correctness():
    """Check that violations.txt contains the correct, sorted violations derived from the CSV files."""
    assert not os.path.islink(LOGS_PATH) and os.path.isfile(LOGS_PATH)
    assert not os.path.islink(PERMS_PATH) and os.path.isfile(PERMS_PATH)
    with open(LOGS_PATH, "rb") as f:
        assert f.read() == ORIGINAL_LOGS, "logs.csv was modified"
    with open(PERMS_PATH, "rb") as f:
        assert f.read() == ORIGINAL_PERMS, "perms.csv was modified"

    logs = []
    with open(LOGS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                logs.append(line.split(","))

    perms = {}
    with open(PERMS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                parts = line.split(",")
                if len(parts) >= 3:
                    perms[(parts[0], parts[1])] = int(parts[2])

    expected_violations = []
    for user_id, resource_id in logs:
        granted = perms.get((user_id, resource_id), 0)
        if granted == 0:
            expected_violations.append(f"{user_id},{resource_id}")
    expected_violations.sort()

    actual_violations = []
    with open(VIOLATIONS_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                actual_violations.append(line)

    assert actual_violations == expected_violations, (
        f"Contents of {VIOLATIONS_PATH} do not match the expected sorted violations.\n"
        f"Expected: {expected_violations}\nActual: {actual_violations}"
    )


def _run_and_check(program, expected):
    with tempfile.TemporaryFile() as output:
        try:
            result = subprocess.run(
                [program], stdout=output, stderr=subprocess.DEVNULL,
                timeout=6, check=False
            )
        except subprocess.TimeoutExpired:
            raise AssertionError(f"{program} did not process the large dataset efficiently")
        assert result.returncode == 0, f"{program} exited with status {result.returncode}"
        output.seek(0)
        raw = output.read()

    try:
        actual = [line.strip() for line in raw.decode("utf-8").splitlines() if line.strip()]
    except UnicodeDecodeError:
        raise AssertionError(f"{program} produced non-text output")
    assert actual == expected, (
        f"{program} did not correctly perform the composite-key join and sorted reporting.\n"
        f"Expected: {expected}\nActual: {actual[:30]}"
    )


def test_source_and_executable_on_large_dynamic_input():
    """Compile the submitted source and exercise both it and the submitted binary."""
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist"
    assert os.path.isfile(SOURCE_PATH) and not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} is not a regular source file"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "audit-from-source")
        compile_result = subprocess.run(
            ["gcc", "-O2", "-std=c11", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, (
            "audit.c does not compile cleanly:\n" +
            compile_result.stderr.decode("utf-8", errors="replace")
        )

        rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
        count = 50000
        users = ["U" + secrets.token_hex(7) for _ in range(count)]
        resources = ["R" + secrets.token_hex(7) for _ in range(count)]
        denied = set(rng.sample(range(count), 9))

        perm_rows = [f"{users[i]},{resources[i]},{0 if i in denied else 1}" for i in range(count)]
        rng.shuffle(perm_rows)

        log_pairs = [(users[i], resources[i]) for i in range(count)]
        # These crossed composite keys have individually known components but no matching pair.
        log_pairs.extend([(users[0], resources[1]), (users[1], resources[0])])
        # These permissions are wholly absent.
        log_pairs.extend([("UM" + secrets.token_hex(6), "RM" + secrets.token_hex(6)) for _ in range(5)])
        rng.shuffle(log_pairs)

        permitted = {(users[i], resources[i]): (0 if i in denied else 1) for i in range(count)}
        expected = sorted(
            f"{u},{r}" for u, r in log_pairs if permitted.get((u, r), 0) == 0
        )
        logs_data = "".join(f"{u},{r}\n" for u, r in log_pairs).encode()
        perms_data = ("\n".join(perm_rows) + "\n").encode()

        try:
            for program in (EXECUTABLE_PATH, rebuilt):
                with open(LOGS_PATH, "wb") as f:
                    f.write(logs_data)
                with open(PERMS_PATH, "wb") as f:
                    f.write(perms_data)
                _run_and_check(program, expected)
                with open(LOGS_PATH, "rb") as f:
                    assert f.read() == logs_data, f"{program} modified logs.csv"
                with open(PERMS_PATH, "rb") as f:
                    assert f.read() == perms_data, f"{program} modified perms.csv"
        finally:
            with open(LOGS_PATH, "wb") as f:
                f.write(ORIGINAL_LOGS)
            with open(PERMS_PATH, "wb") as f:
                f.write(ORIGINAL_PERMS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
