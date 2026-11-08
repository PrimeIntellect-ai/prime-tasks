#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import subprocess
import tempfile
import pytest


def test_auth_parser_tests_pass():
    """Verify the package tests and the nested-group behavior described by the task."""
    work_dir = "/app/vendored/auth_parser-1.2.0"
    assert os.path.isdir(work_dir), f"Directory {work_dir} does not exist."

    result = subprocess.run(
        ["python3", "-m", "unittest", "discover"],
        cwd=work_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Tests failed in {work_dir}. Stderr: {result.stderr}"

    check = subprocess.run(
        [
            "python3",
            "-c",
            "from auth_parser.core import validate_access_token, Token; "
            "t=Token(); "
            "assert validate_access_token([['admins']], t) is True; "
            "assert validate_access_token([], t) is False; "
            "t.is_valid=False; "
            "assert validate_access_token([['admins']], t) is False",
        ],
        cwd=work_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert check.returncode == 0, f"Nested-group validation is still broken: {check.stderr}"


def test_cracked_password():
    """Verify that the cracked password file exists and contains the correct password."""
    path = "/home/user/audit_logs/cracked_pass.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert content.strip() == "apple", f"Expected cracked password 'apple', got '{content.strip()}'"


def _drop_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_evaluator_agent_fuzz():
    """Exercise the submitted executable while the reference oracle is unavailable to it."""
    oracle_path = "/opt/oracle/perm_eval_oracle"
    oracle_dir = os.path.dirname(oracle_path)
    agent_path = "/home/user/evaluator_agent"

    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} not found."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} not found."
    assert not os.path.islink(agent_path), "Agent script must not be a symbolic link."
    assert stat.S_ISREG(os.stat(agent_path).st_mode), "Agent script must be a regular file."
    assert os.access(agent_path, os.X_OK), f"Agent script {agent_path} is not executable."

    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "The submitted evaluator must not be a byte-identical copy of the oracle."

    random.seed(42)
    cases = [
        (b"", b""),
        (b"", bytes(range(256))),
        (bytes(range(256)), b""),
        (bytes(range(256)), bytes(reversed(range(256)))),
    ]
    for _ in range(5000):
        len1 = random.randint(1, 1024)
        len2 = random.randint(1, 1024)
        data1 = bytes(random.randint(0, 255) for _ in range(len1))
        data2 = bytes(random.randint(0, 255) for _ in range(len2))
        cases.append((data1, data2))

    hidden_oracle = os.path.join(oracle_dir, ".perm_eval_oracle.verifier_hidden")
    original_dir_mode = stat.S_IMODE(os.stat(oracle_dir).st_mode)

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        file1_path = os.path.join(tmpdir, "input1.bin")
        file2_path = os.path.join(tmpdir, "input2.bin")
        expected_results = []

        # Preserve the original oracle comparison, while also deriving the expected
        # answer independently rather than trusting the reference executable.
        for i, (data1, data2) in enumerate(cases):
            with open(file1_path, "wb") as f1, open(file2_path, "wb") as f2:
                f1.write(data1)
                f2.write(data2)
            expected = bytes(a ^ b for a, b in zip(data1, data2))
            oracle_res = subprocess.run(
                [oracle_path, file1_path, file2_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            assert oracle_res.returncode == 0, f"Oracle failed on case {i + 1}."
            assert oracle_res.stdout == expected, f"Oracle disagreed with derived result on case {i + 1}."
            expected_results.append(expected)

        os.rename(oracle_path, hidden_oracle)
        os.chmod(oracle_dir, 0o700)
        try:
            for i, ((data1, data2), expected) in enumerate(zip(cases, expected_results)):
                with open(file1_path, "wb") as f1, open(file2_path, "wb") as f2:
                    f1.write(data1)
                    f2.write(data2)
                os.chmod(file1_path, 0o644)
                os.chmod(file2_path, 0o644)

                try:
                    agent_res = subprocess.run(
                        [agent_path, file1_path, file2_path],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=5,
                        preexec_fn=_drop_to_user,
                    )
                except subprocess.TimeoutExpired:
                    pytest.fail(f"Evaluator timed out on case {i + 1}.")

                if agent_res.returncode != 0 or agent_res.stdout != expected:
                    pytest.fail(
                        f"Mismatch on case {i + 1}:\n"
                        f"Input 1 length: {len(data1)}, Input 2 length: {len(data2)}\n"
                        f"Expected returncode: 0, Agent returncode: {agent_res.returncode}\n"
                        f"Expected stdout (hex): {expected.hex()[:100]}...\n"
                        f"Agent stdout (hex): {agent_res.stdout.hex()[:100]}...\n"
                    )
        finally:
            os.chmod(oracle_dir, original_dir_mode)
            os.rename(hidden_oracle, oracle_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
