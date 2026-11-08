#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import stat
import subprocess
import pytest

SCRIPT = "/home/user/ticket_repo/calculate.sh"


def get_collatz_steps(n):
    count = 0
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        count += 1
    return count


def expected_output(n):
    return "".join(f"{i}: {get_collatz_steps(i)}\n" for i in range(1, n + 1))


def run_script(n):
    try:
        result = subprocess.run(
            [SCRIPT, str(n)],
            cwd="/home/user/ticket_repo",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT} did not terminate for input {n}.")

    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode} for input {n}. "
        f"stderr: {result.stderr!r}"
    )
    assert result.stdout == expected_output(n), (
        f"{SCRIPT} produced incorrect stdout for input {n}."
    )
    return result.stdout


def test_recovered_password():
    password_file = "/home/user/recovered_password.txt"
    assert os.path.exists(password_file), f"File {password_file} does not exist."

    with open(password_file, "r") as f:
        content = f.read().strip()

    expected_password = "h4ckth3m4th!99"
    assert content == expected_password, f"Recovered password is incorrect. Expected '{expected_password}', got '{content}'."


def test_collatz_output():
    output_file = "/home/user/collatz_20.txt"
    assert os.path.exists(output_file), f"File {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 20, f"Expected 20 lines of output in {output_file}, but found {len(lines)}."

    for i in range(1, 21):
        expected_steps = get_collatz_steps(i)
        expected_line = f"{i}: {expected_steps}"
        actual_line = lines[i-1]
        assert actual_line == expected_line, f"Line {i} is incorrect. Expected '{expected_line}', got '{actual_line}'."


def test_calculate_script_is_fixed_and_executed():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    random_n = 21 + secrets.randbelow(60)
    run_script(random_n)
    stdout_20 = run_script(20)

    with open("/home/user/collatz_20.txt", "rb") as f:
        saved_output = f.read()
    assert saved_output == stdout_20.encode(), (
        "/home/user/collatz_20.txt is not the exact stdout of calculate.sh 20."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
