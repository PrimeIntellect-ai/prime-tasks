#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

REPO_PATH = "/home/user/repo"
CALC_SOURCE = os.path.join(REPO_PATH, "calc.c")
CALC_BIN = os.path.join(REPO_PATH, "calc")
ORACLE_BIN = "/home/user/legacy/oracle"


def get_bad_commit_hash():
    try:
        log_output = subprocess.check_output(
            ["git", "-c", f"safe.directory={REPO_PATH}", "log", "--format=%H %s"],
            cwd=REPO_PATH,
            text=True,
        )
        for line in log_output.strip().split("\n"):
            if "Refactor calculation logic" in line:
                return line.split()[0]
    except subprocess.CalledProcessError:
        pass
    return None


def run_program(path, x, y):
    result = subprocess.run(
        [path, str(x), str(y)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{path} failed for x={x}, y={y}: {result.stderr.strip()}"
    )
    return result.stdout.strip()


def test_resolution_file_exists():
    assert os.path.isfile("/home/user/resolution.txt"), "The file /home/user/resolution.txt does not exist."


def test_resolution_file_contents():
    resolution_path = "/home/user/resolution.txt"
    with open(resolution_path, "r") as f:
        content = f.read()

    req_match = re.search(r"First failing REQ:\s*(.+)", content)
    inputs_match = re.search(r"Failing inputs:\s*(.+)", content)
    commit_match = re.search(r"Overflow commit:\s*(.+)", content)
    constant_match = re.search(r"Oracle XOR constant:\s*(.+)", content)
    output_match = re.search(r"Fixed program output for failing inputs:\s*(.+)", content)

    assert req_match, "Could not find 'First failing REQ' in resolution.txt"
    assert req_match.group(1).strip() == "REQ-1003", "Incorrect first failing REQ"

    assert inputs_match, "Could not find 'Failing inputs' in resolution.txt"
    assert inputs_match.group(1).strip() == "x=85000 y=92000", "Incorrect failing inputs"

    bad_commit = get_bad_commit_hash()
    assert bad_commit is not None, "Could not find the bad commit in git history"

    assert commit_match, "Could not find 'Overflow commit' in resolution.txt"
    assert commit_match.group(1).strip() == bad_commit, "Incorrect overflow commit hash"

    assert constant_match, "Could not find 'Oracle XOR constant' in resolution.txt"
    assert constant_match.group(1).strip().upper() == "0XCAFEBABE", "Incorrect Oracle XOR constant"

    assert output_match, "Could not find 'Fixed program output for failing inputs' in resolution.txt"
    assert output_match.group(1).strip() == "4712030654", "Incorrect fixed program output"


def test_fixed_calc_program():
    assert os.path.isfile(CALC_BIN), "The compiled binary /home/user/repo/calc does not exist."
    assert os.access(CALC_BIN, os.X_OK), "The file /home/user/repo/calc is not executable."

    try:
        output = subprocess.check_output([CALC_BIN, "85000", "92000"], text=True).strip()
        assert output == "4712030654", f"The compiled binary produced incorrect output: {output} instead of 4712030654"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run the compiled binary: {e}")


def test_calc_source_builds_and_matches_oracle_generally():
    assert os.path.isfile(CALC_SOURCE), "The source file /home/user/repo/calc.c does not exist."
    assert os.path.isfile(ORACLE_BIN) and os.access(ORACLE_BIN, os.X_OK), "Oracle binary is unavailable."

    with open(CALC_BIN, "rb") as submitted, open(ORACLE_BIN, "rb") as oracle:
        assert submitted.read() != oracle.read(), "The submitted calc binary is byte-identical to the oracle."

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_calc = os.path.join(temp_dir, "calc")
        build = subprocess.run(
            ["gcc", "-fwrapv", "-O0", "-g", CALC_SOURCE, "-o", rebuilt_calc],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, f"calc.c failed to compile: {build.stderr}"

        cases = [
            (0, 0),
            (1, 1),
            (10, 20),
            (500, 300),
            (85000, 92000),
            (90000, 90000),
            (-123456, 78901),
            (1500000, -1700000),
        ]
        for _ in range(20):
            x = secrets.randbelow(4000001) - 2000000
            y = secrets.randbelow(4000001) - 2000000
            cases.append((x, y))

        for x, y in cases:
            expected = run_program(ORACLE_BIN, x, y)
            assert run_program(CALC_BIN, x, y) == expected, (
                f"The compiled repository binary disagrees with the oracle for x={x}, y={y}"
            )
            assert run_program(rebuilt_calc, x, y) == expected, (
                f"A fresh build of calc.c disagrees with the oracle for x={x}, y={y}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
