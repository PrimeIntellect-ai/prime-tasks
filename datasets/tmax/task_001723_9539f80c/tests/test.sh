#!/bin/bash
set -e
mkdir -p /logs/verifier

GUARD_DIR="$(mktemp -d /tmp/verifier_guard.XXXXXX)"
chmod 755 "$GUARD_DIR"
cat << 'GUARD_EOF' > "$GUARD_DIR/sitecustomize.py"
import sys

_BLOCKED_EVENTS = {
    "os.exec",
    "os.fork",
    "os.forkpty",
    "os.posix_spawn",
    "os.system",
    "ctypes.dlopen",
    "ctypes.dlsym",
}

def _guard(event, args):
    if event in _BLOCKED_EVENTS or event.startswith("subprocess."):
        raise RuntimeError("external process execution is disabled during verification")
    if event == "import" and args and args[0] == "_posixsubprocess":
        raise RuntimeError("direct process execution is disabled during verification")

sys.addaudithook(_guard)
GUARD_EOF
chmod 644 "$GUARD_DIR/sitecustomize.py"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import subprocess
import tempfile
import pytest

STUDENT_SCRIPT = "/home/user/proxy_check.py"
ORACLE_BIN = "/app/oracle_proxy_check"
GUARD_DIR = os.environ["VERIFIER_GUARD_DIR"]


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def expected_output(hex_input):
    third = int(hex_input[0:2], 16) % 256
    fourth = int(hex_input[2:4], 16) % 256
    port = 8000 + int(hex_input[12:16], 16)
    return f"10.100.{third}.{fourth}:{port}"


def test_proxy_check_fuzz_equivalence():
    assert os.path.exists(STUDENT_SCRIPT), f"Student script missing at {STUDENT_SCRIPT}"
    assert os.path.isfile(STUDENT_SCRIPT), f"Student script is not a regular file: {STUDENT_SCRIPT}"
    assert not os.path.islink(STUDENT_SCRIPT), f"Student script must not be a symbolic link: {STUDENT_SCRIPT}"
    mode = os.stat(STUDENT_SCRIPT).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "Student script is not executable"
    assert os.path.exists(ORACLE_BIN), f"Oracle binary missing at {ORACLE_BIN}"

    random.seed(42)
    cases = ["".join(random.choices("0123456789abcdef", k=16)) for _ in range(1000)]
    oracle_outputs = []

    # Preserve the original oracle-equivalence assertion, while also deriving
    # every expected answer independently.
    for hex_input in cases:
        try:
            oracle_proc = subprocess.run(
                [ORACLE_BIN, hex_input],
                capture_output=True,
                text=True,
                timeout=2,
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle failed on input {hex_input} with error: {exc.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {hex_input}")

        derived = expected_output(hex_input)
        assert oracle_proc.stdout == derived + "\n", (
            f"Oracle disagrees with independently derived result on input {hex_input}"
        )
        oracle_outputs.append(derived)

    # Make the recovered oracle inaccessible while student code runs. Student
    # processes are also demoted and guarded against launching copied helpers.
    hidden_dir = tempfile.mkdtemp(prefix=".proxy-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle_proxy_check")
    os.replace(ORACLE_BIN, hidden_oracle)

    try:
        env = os.environ.copy()
        env["PYTHONPATH"] = GUARD_DIR
        env["HOME"] = "/home/user"

        for hex_input, oracle_out in zip(cases, oracle_outputs):
            try:
                student_proc = subprocess.run(
                    ["python3", STUDENT_SCRIPT, hex_input],
                    capture_output=True,
                    text=True,
                    timeout=2,
                    env=env,
                    preexec_fn=demote_to_user,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Student script timed out on input {hex_input}")

            student_out = student_proc.stdout.strip()
            assert student_proc.returncode == 0, (
                f"Student script exited with code {student_proc.returncode} on input {hex_input}.\n"
                f"Stderr: {student_proc.stderr}"
            )
            assert student_out == oracle_out, (
                f"Output mismatch on input {hex_input}.\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Actual (Student):  {student_out}"
            )
            assert student_proc.stdout == oracle_out + "\n", (
                f"Output must be exactly one correctly formatted line on input {hex_input}"
            )
    finally:
        os.replace(hidden_oracle, ORACLE_BIN)
        os.rmdir(hidden_dir)
TEST_EOF

if VERIFIER_GUARD_DIR="$GUARD_DIR" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$GUARD_DIR"
