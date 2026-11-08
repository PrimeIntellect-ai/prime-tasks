#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import shutil
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/legacy_transform"
AGENT_PATH = "/home/user/new_transform"
SOURCE_PATH = "/home/user/new_transform.c"
CONFLICTING_HEADER = "/usr/local/include/math_utils/special.h"
REBUILT_PATH = "/tmp/verifier_new_transform"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def make_jail(program):
    jail = tempfile.mkdtemp(prefix="transform-jail-")
    os.chmod(jail, 0o755)
    shutil.copy2(program, os.path.join(jail, "program"))
    os.chmod(os.path.join(jail, "program"), 0o755)

    ldd = subprocess.run(
        ["ldd", program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, check=True
    )
    libraries = set()
    for line in ldd.stdout.splitlines():
        for token in line.replace("=>", " ").split():
            if token.startswith("/") and os.path.exists(token):
                libraries.add(token)

    for library in libraries:
        destination = os.path.join(jail, library.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(library, destination)
        os.chmod(destination, 0o755)
    return jail


def run_in_jail(jail, input_bytes, timeout=10):
    def isolate():
        os.chroot(jail)
        os.chdir("/")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)

    return subprocess.run(
        ["/program"],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=isolate,
    )


@pytest.fixture(scope="session")
def tested_programs():
    assert os.path.exists(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"
    assert not os.path.exists(CONFLICTING_HEADER), (
        f"Conflicting header was not cleaned up: {CONFLICTING_HEADER}"
    )

    compile_proc = subprocess.run(
        ["gcc", "-pthread", "-O3", SOURCE_PATH, "-o", REBUILT_PATH, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        "new_transform.c does not compile with standard gcc flags:\n"
        + compile_proc.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)

    agent_jail = make_jail(AGENT_PATH)
    rebuilt_jail = make_jail(REBUILT_PATH)
    try:
        yield agent_jail, rebuilt_jail
    finally:
        shutil.rmtree(agent_jail, ignore_errors=True)
        shutil.rmtree(rebuilt_jail, ignore_errors=True)
        try:
            os.remove(REBUILT_PATH)
        except FileNotFoundError:
            pass


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"{ORACLE_PATH} is not executable"
    assert file_hash(AGENT_PATH) != file_hash(ORACLE_PATH), (
        "Agent binary is byte-identical to the legacy executable"
    )


def test_fuzz_equivalence(tested_programs):
    agent_jail, rebuilt_jail = tested_programs

    random.seed(42)
    N = 50
    for i in range(N):
        size = random.randint(100, 10000)
        input_floats = [random.uniform(-1000.0, 1000.0) for _ in range(size)]
        input_str = " ".join(f"{x:.6f}" for x in input_floats) + "\n"
        input_bytes = input_str.encode("utf-8")

        oracle_proc = subprocess.run(
            [ORACLE_PATH], input=input_bytes, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_out = oracle_proc.stdout

        for label, jail in (("agent binary", agent_jail),
                            ("binary rebuilt from new_transform.c", rebuilt_jail)):
            proc = run_in_jail(jail, input_bytes)
            assert proc.returncode == 0, (
                f"{label} failed on iteration {i} with stderr: "
                + proc.stderr.decode("utf-8", errors="replace")
            )
            if proc.stdout != oracle_out:
                pytest.fail(
                    f"Mismatch for {label} on iteration {i} with input size {size}.\n"
                    f"Input sample: {input_str[:100]}...\n"
                    f"Oracle output sample: {oracle_out[:100]!r}...\n"
                    f"Program output sample: {proc.stdout[:100]!r}..."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
