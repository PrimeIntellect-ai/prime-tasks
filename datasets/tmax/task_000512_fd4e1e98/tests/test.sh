#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import re
import shutil
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/legacy_archiver"
AGENT_PATH = "/home/user/archiver"
SOURCE_PATH = "/home/user/archiver.cpp"
USER_INFO = pwd.getpwnam("user")


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.digest()


def make_sandbox(executable):
    root = tempfile.mkdtemp(prefix="archiver-sandbox-")
    os.chmod(root, 0o755)
    shutil.copy2(executable, os.path.join(root, "prog"))
    os.chmod(os.path.join(root, "prog"), 0o755)

    ldd = subprocess.run(
        ["ldd", executable], capture_output=True, text=True, check=True
    ).stdout
    libraries = set()
    for line in ldd.splitlines():
        match = re.search(r"=>\s+(/[^ ]+)", line)
        if match:
            libraries.add(match.group(1))
            continue
        match = re.match(r"\s*(/[^ ]+)\s+\(", line)
        if match:
            libraries.add(match.group(1))

    for library in libraries:
        destination = os.path.join(root, library.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(library, destination)

    return root


def sandbox_preexec(root):
    def prepare():
        os.chroot(root)
        os.chdir("/")
        os.setgroups([])
        os.setgid(USER_INFO.pw_gid)
        os.setuid(USER_INFO.pw_uid)
    return prepare


def user_preexec():
    os.setgroups([])
    os.setgid(USER_INFO.pw_gid)
    os.setuid(USER_INFO.pw_uid)


@pytest.fixture(scope="session")
def artifacts():
    assert os.path.exists(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Source path {SOURCE_PATH} is not a file"
    assert not os.path.islink(SOURCE_PATH), "Source must not be a symlink"

    build_dir = tempfile.mkdtemp(prefix="archiver-build-")
    compiled_path = os.path.join(build_dir, "archiver-from-source")
    build = subprocess.run(
        ["g++", "-O2", "-std=c++17", SOURCE_PATH, "-o", compiled_path],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"archiver.cpp failed to compile:\n{build.stderr}"

    assert file_hash(AGENT_PATH) != file_hash(ORACLE_PATH), (
        "Submitted executable is byte-identical to the legacy binary"
    )
    assert file_hash(compiled_path) != file_hash(ORACLE_PATH), (
        "Executable built from archiver.cpp is byte-identical to the legacy binary"
    )

    sandbox = make_sandbox(compiled_path)
    try:
        yield {"compiled": compiled_path, "sandbox": sandbox}
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent path {AGENT_PATH} is not a file"
    assert not os.path.islink(AGENT_PATH), "Agent binary must not be a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), (
        "Agent executable must not be the legacy binary"
    )


def test_source_builds(artifacts):
    assert os.path.isfile(artifacts["compiled"])
    assert os.access(artifacts["compiled"], os.X_OK)


def test_fuzz_equivalence(artifacts):
    rng = random.Random(42)
    hidden_oracle = os.path.join(
        "/root", ".legacy_archiver_hidden_" + next(tempfile._get_candidate_names())
    )

    for i in range(100):
        size = rng.randint(0, 5 * 1024 * 1024)
        input_data = os.urandom(size)

        oracle_proc = subprocess.run(
            [ORACLE_PATH], input=input_data, capture_output=True, timeout=30
        )

        # Make the supplied oracle inaccessible while either submitted artifact runs.
        os.rename(ORACLE_PATH, hidden_oracle)
        try:
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_data,
                capture_output=True,
                timeout=30,
                cwd="/home/user",
                preexec_fn=user_preexec,
            )
            compiled_proc = subprocess.run(
                ["/prog"],
                input=input_data,
                capture_output=True,
                timeout=30,
                preexec_fn=sandbox_preexec(artifacts["sandbox"]),
            )
        finally:
            os.rename(hidden_oracle, ORACLE_PATH)

        for description, proc in (
            ("Agent executable", agent_proc),
            ("Executable rebuilt from source", compiled_proc),
        ):
            assert oracle_proc.returncode == proc.returncode, (
                f"{description} return code mismatch on iteration {i} "
                f"(input size {size}). Oracle: {oracle_proc.returncode}, "
                f"submission: {proc.returncode}"
            )

            if oracle_proc.stdout != proc.stdout:
                mismatch_len = min(len(oracle_proc.stdout), len(proc.stdout))
                diff_idx = next(
                    (j for j in range(mismatch_len)
                     if oracle_proc.stdout[j] != proc.stdout[j]),
                    mismatch_len,
                )
                pytest.fail(
                    f"{description} stdout mismatch on iteration {i} "
                    f"(input size {size}).\n"
                    f"Oracle output length: {len(oracle_proc.stdout)}\n"
                    f"Submission output length: {len(proc.stdout)}\n"
                    f"First differing byte index: {diff_idx}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
