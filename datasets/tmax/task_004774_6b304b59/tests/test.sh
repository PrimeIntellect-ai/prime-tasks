#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import subprocess

import pytest

REPO = "/home/user/fxhash_repo"
FIXED = "/home/user/fxhash_fixed"
ORACLE = "/app/fxhash_legacy"
REBUILT = "/tmp/fxhash_rebuilt"


def run_binary(path, data, timeout=2):
    try:
        proc = subprocess.run(
            [path],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"{path} failed. Stderr: "
            f"{e.stderr.decode('utf-8', errors='replace')}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out.")
    return proc.stdout.decode("utf-8").strip()


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def go_build_info(path):
    proc = subprocess.run(
        ["go", "version", "-m", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert proc.returncode == 0, (
        f"{path} is not a valid Go executable: {proc.stderr}"
    )

    info = {}
    for line in proc.stdout.splitlines()[1:]:
        fields = line.strip().split("\t")
        if len(fields) >= 2:
            info[fields[0]] = fields[1]
    return info


@pytest.fixture(scope="session", autouse=True)
def verify_and_build_repository():
    assert os.path.isdir(REPO), f"Repository {REPO} is missing."

    go_mod = os.path.join(REPO, "go.mod")
    main_go = os.path.join(REPO, "main.go")
    assert os.path.isfile(go_mod), f"{go_mod} is missing."
    assert os.path.isfile(main_go), f"{main_go} is missing."

    with open(go_mod, "r", encoding="utf-8") as f:
        go_mod_text = f.read()
    assert "/nonexistent/path" not in go_mod_text, (
        "go.mod still contains the broken replacement to /nonexistent/path."
    )

    proc = subprocess.run(
        ["go", "build", "-o", REBUILT, "."],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, (
        "The repaired repository does not compile successfully.\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_fixed_binary_exists_and_executable():
    fixed_bin_path = FIXED
    assert os.path.exists(fixed_bin_path), f"Fixed binary {fixed_bin_path} is missing."
    assert os.path.isfile(fixed_bin_path), f"{fixed_bin_path} is not a file."
    assert os.access(fixed_bin_path, os.X_OK), f"Fixed binary {fixed_bin_path} is not executable."


def test_fixed_binary_was_built_as_fxhash_module():
    assert os.path.exists(ORACLE), f"Oracle binary {ORACLE} missing."
    assert file_sha256(FIXED) != file_sha256(ORACLE), (
        "The submitted executable is byte-identical to the legacy oracle."
    )

    rebuilt_info = go_build_info(REBUILT)
    fixed_info = go_build_info(FIXED)
    assert rebuilt_info.get("path") == "fxhash", (
        f"Verifier-built repository has unexpected Go package path: {rebuilt_info.get('path')!r}"
    )
    assert fixed_info.get("path") == rebuilt_info.get("path"), (
        "The submitted executable was not built as the fxhash repository module."
    )
    assert fixed_info.get("mod") == rebuilt_info.get("mod") == "fxhash", (
        "The submitted executable does not contain fxhash module build metadata."
    )


def test_fuzz_equivalence():
    oracle_path = ORACLE
    agent_path = FIXED

    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} missing."
    assert os.path.exists(agent_path), f"Agent binary {agent_path} missing."

    random.seed(42)
    N = 1000
    min_len = 100
    max_len = 100000

    for i in range(N):
        length = random.randint(min_len, max_len)
        test_input = bytearray(random.getrandbits(8) for _ in range(length))

        oracle_out = run_binary(oracle_path, test_input)
        agent_out = run_binary(agent_path, test_input)
        rebuilt_out = run_binary(REBUILT, test_input)

        assert agent_out == oracle_out, (
            f"Output mismatch on random input {i} (length {length}).\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
        assert rebuilt_out == oracle_out, (
            f"Repository source mismatch on random input {i} (length {length}).\n"
            f"Oracle output: {oracle_out}\n"
            f"Rebuilt output: {rebuilt_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
