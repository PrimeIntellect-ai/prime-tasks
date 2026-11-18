#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_aggregator"
AGENT_PATH = "/home/user/etl_transformer"
SOURCE_PATH = "/home/user/etl_transformer.c"


def generate_random_utf8(length):
    chars = []
    for _ in range(length):
        cp = random.randint(0, 0x10FFFF)
        if 0xD800 <= cp <= 0xDFFF:
            cp = 0x0020
        chars.append(chr(cp))
    return "".join(chars).encode("utf-8")


def drop_to_user():
    user = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def enter_sandbox_and_drop(sandbox):
    def setup():
        os.chroot(sandbox)
        os.chdir("/")
        drop_to_user()
    return setup


def assert_regular_file(path, description):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{description} at {path} is not a regular file"


def compare_result(i, length, expected, actual, label):
    if expected.stdout != actual.stdout:
        pytest.fail(
            f"Iteration {i}: {label} stdout mismatch.\n"
            f"Input length: {length} chars\n"
            f"Oracle stdout (first 200 bytes): {expected.stdout[:200]}\n"
            f"Candidate stdout (first 200 bytes): {actual.stdout[:200]}"
        )
    if expected.stderr != actual.stderr:
        pytest.fail(
            f"Iteration {i}: {label} stderr mismatch.\n"
            f"Input length: {length} chars\n"
            f"Oracle stderr (first 200 bytes): {expected.stderr[:200]}\n"
            f"Candidate stderr (first 200 bytes): {actual.stderr[:200]}"
        )
    if expected.returncode != actual.returncode:
        pytest.fail(
            f"Iteration {i}: {label} returncode mismatch.\n"
            f"Oracle returned {expected.returncode}, Candidate returned {actual.returncode}"
        )


def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program at {AGENT_PATH} is not executable"
    assert_regular_file(AGENT_PATH, "Agent executable")

    assert os.path.exists(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Path {SOURCE_PATH} is not a file"
    assert_regular_file(SOURCE_PATH, "C source")

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent executable is byte-identical to the legacy binary"

    random.seed(42)
    cases = []
    for _ in range(100):
        length = random.randint(0, 5000)
        cases.append((length, generate_random_utf8(length)))

    expected = []
    for _, input_data in cases:
        expected.append(subprocess.run([ORACLE_PATH], input=input_data, capture_output=True))

    hidden_dir = tempfile.mkdtemp(prefix="verifier_oracle_")
    sandbox = tempfile.mkdtemp(prefix="verifier_sandbox_")
    hidden_oracle = os.path.join(hidden_dir, "legacy_aggregator")
    os.chmod(hidden_dir, 0o700)
    os.chmod(sandbox, 0o755)

    try:
        os.rename(ORACLE_PATH, hidden_oracle)

        compiled_path = os.path.join(sandbox, "prog")
        compile_proc = subprocess.run(
            ["gcc", "-O2", "-static", SOURCE_PATH, "-o", compiled_path],
            capture_output=True,
            text=True,
        )
        assert compile_proc.returncode == 0, (
            "Failed to compile the submitted C source:\n"
            + compile_proc.stdout
            + compile_proc.stderr
        )
        assert_regular_file(compiled_path, "Recompiled program")
        os.chmod(compiled_path, 0o755)

        for i, ((length, input_data), oracle_proc) in enumerate(zip(cases, expected)):
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_data,
                capture_output=True,
                preexec_fn=drop_to_user,
                timeout=15,
            )
            compare_result(i, length, oracle_proc, agent_proc, "agent executable")

            source_proc = subprocess.run(
                ["/prog"],
                input=input_data,
                capture_output=True,
                preexec_fn=enter_sandbox_and_drop(sandbox),
                timeout=15,
            )
            compare_result(i, length, oracle_proc, source_proc, "recompiled source")
    finally:
        if os.path.exists(hidden_oracle) and not os.path.exists(ORACLE_PATH):
            os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir, ignore_errors=True)
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
