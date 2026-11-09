#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import subprocess
import tempfile
import pytest

C_PATH = "/home/user/hasher_rebuilt.c"
BIN_PATH = "/home/user/hasher_rebuilt"
ORACLE_PATH = "/app/legacy_hasher"


def run_program(path, value, timeout=2, preexec_fn=None):
    try:
        return subprocess.run(
            [path, value],
            capture_output=True,
            text=True,
            timeout=timeout,
            preexec_fn=preexec_fn,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program {path} timed out on input: {value!r}")


def test_agent_files_exist():
    """Verify that the agent has created the required source and compiled binary."""
    assert os.path.exists(C_PATH), f"Source file {C_PATH} is missing."
    assert os.path.isfile(C_PATH), f"Source path {C_PATH} is not a regular file."
    assert os.path.exists(BIN_PATH), f"Compiled binary {BIN_PATH} is missing."
    assert os.path.isfile(BIN_PATH), f"Compiled path {BIN_PATH} is not a regular file."
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."

    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BIN_PATH} is not an ELF binary."


def test_fuzz_equivalence_without_oracle_access():
    """Compare against oracle-derived answers, then test with the oracle removed."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} is missing."
    assert os.path.exists(BIN_PATH), f"Agent binary {BIN_PATH} is missing."

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(BIN_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submitted binary is byte-identical to the oracle."

    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation + " "
    inputs = [
        "".join(random.choice(charset) for _ in range(random.randint(0, 64)))
        for _ in range(1000)
    ]

    expected = []
    for test_input in inputs:
        oracle_res = run_program(ORACLE_PATH, test_input)
        expected.append((oracle_res.returncode, oracle_res.stdout))

    # Recompile the submitted source independently as a static executable. It is
    # later run in an empty chroot, so it cannot invoke the legacy oracle or any
    # copy located elsewhere in the normal filesystem.
    jail = tempfile.mkdtemp(prefix="hasher-jail-")
    isolated_binary = os.path.join(jail, "candidate")
    compile_res = subprocess.run(
        ["gcc", "-O2", "-static", C_PATH, "-o", isolated_binary],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_res.returncode == 0, (
        "Submitted source could not be independently compiled with gcc.\n"
        f"stdout: {compile_res.stdout}\nstderr: {compile_res.stderr}"
    )
    os.chmod(isolated_binary, 0o755)

    # Remove the oracle before executing either submitted artifact. Expected
    # results have already been captured above.
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)

    def enter_empty_chroot():
        os.chroot(jail)
        os.chdir("/")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)

    try:
        for test_input, (oracle_rc, oracle_out) in zip(inputs, expected):
            agent_res = run_program(BIN_PATH, test_input)
            assert agent_res.returncode == oracle_rc, (
                f"Return code mismatch on input {test_input!r}.\n"
                f"Oracle: {oracle_rc}, Agent: {agent_res.returncode}"
            )
            assert agent_res.stdout == oracle_out, (
                f"Output mismatch on input {test_input!r}.\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output:  {agent_res.stdout!r}"
            )

            isolated_res = run_program(
                "/candidate", test_input, preexec_fn=enter_empty_chroot
            )
            assert isolated_res.returncode == oracle_rc, (
                f"Independently compiled source returned the wrong code on "
                f"input {test_input!r}.\n"
                f"Oracle: {oracle_rc}, Rebuilt source: {isolated_res.returncode}"
            )
            assert isolated_res.stdout == oracle_out, (
                f"Independently compiled source produced the wrong output on "
                f"input {test_input!r}.\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Rebuilt output: {isolated_res.stdout!r}"
            )
    finally:
        shutil.rmtree(jail, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
