#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pwd
import random
import shutil
import subprocess
import tempfile

import pytest

AGENT_PATH = "/home/user/rust_scorer/target/release/rust_scorer"
PROJECT_PATH = "/home/user/rust_scorer"
ORACLE_PATH = "/app/seq_align_scorer"
SCRIPT_PATH = "/home/user/test_scorer.sh"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.digest()


def expected_score(seq1, seq2):
    match = 4
    mismatch = -3
    gap = -2
    previous = [j * gap for j in range(len(seq2) + 1)]
    for i, c1 in enumerate(seq1, 1):
        current = [i * gap]
        for j, c2 in enumerate(seq2, 1):
            current.append(max(
                previous[j - 1] + (match if c1 == c2 else mismatch),
                previous[j] + gap,
                current[j - 1] + gap,
            ))
        previous = current
    return str(previous[-1])


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary"
    assert sha256(AGENT_PATH) != sha256(ORACLE_PATH), "Agent binary is identical to the legacy binary"


def test_bash_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Bash script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    subprocess.run(["bash", "-n", SCRIPT_PATH], check=True, timeout=10)


def _exercise_regression_script(oracle_value, agent_value, log_path):
    protected = tempfile.mkdtemp(prefix="regression-originals-")
    os.chmod(protected, 0o700)
    saved_oracle = os.path.join(protected, "oracle")
    saved_agent = os.path.join(protected, "agent")
    os.replace(ORACLE_PATH, saved_oracle)
    os.replace(AGENT_PATH, saved_agent)

    def write_wrapper(path, label, value):
        code = f'''#!/usr/bin/python3
import json
import sys
with open({log_path!r}, "a") as f:
    json.dump([{label!r}] + sys.argv[1:], f)
    f.write("\\n")
print({value!r})
'''
        with open(path, "w") as f:
            f.write(code)
        os.chmod(path, 0o755)

    try:
        write_wrapper(ORACLE_PATH, "oracle", oracle_value)
        write_wrapper(AGENT_PATH, "agent", agent_value)
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", SCRIPT_PATH],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        return result
    finally:
        for path in (ORACLE_PATH, AGENT_PATH):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        os.replace(saved_oracle, ORACLE_PATH)
        os.replace(saved_agent, AGENT_PATH)
        os.rmdir(protected)


def test_regression_script_runs_50_pairs_and_asserts_equality():
    fd, log_path = tempfile.mkstemp(prefix="regression-calls-", suffix=".jsonl")
    os.close(fd)
    os.chmod(log_path, 0o666)
    try:
        equal_run = _exercise_regression_script("0", "0", log_path)
        assert equal_run.returncode == 0, (
            "Regression script failed when both scorers agreed:\n"
            + equal_run.stdout + equal_run.stderr
        )

        calls = []
        with open(log_path) as f:
            for line in f:
                calls.append(json.loads(line))

        oracle_pairs = set()
        agent_pairs = set()
        for call in calls:
            assert len(call) == 3, "Each scorer invocation must receive exactly two sequences"
            label, seq1, seq2 = call
            assert seq1 and seq2, "Regression sequences must be non-empty"
            assert set(seq1) <= set("ACGT") and set(seq2) <= set("ACGT"), "Regression inputs must be DNA sequences"
            if label == "oracle":
                oracle_pairs.add((seq1, seq2))
            elif label == "agent":
                agent_pairs.add((seq1, seq2))

        common_pairs = oracle_pairs & agent_pairs
        assert len(common_pairs) >= 50, (
            f"Regression script must run both scorers on at least 50 generated pairs; saw {len(common_pairs)}"
        )

        open(log_path, "w").close()
        mismatch_run = _exercise_regression_script("0", "1", log_path)
        assert mismatch_run.returncode != 0, "Regression script did not fail when scorer outputs differed"
    finally:
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"

    random.seed(42)
    chars = ['A', 'C', 'G', 'T']

    for i in range(1000):
        len1 = random.randint(5, 60)
        len2 = random.randint(5, 60)
        seq1 = "".join(random.choices(chars, k=len1))
        seq2 = "".join(random.choices(chars, k=len2))

        try:
            oracle_out = subprocess.check_output([ORACLE_PATH, seq1, seq2], text=True).strip()
        except subprocess.CalledProcessError:
            pytest.fail(f"Oracle failed on inputs: {seq1}, {seq2}")

        try:
            agent_out = subprocess.check_output([AGENT_PATH, seq1, seq2], text=True).strip()
        except subprocess.CalledProcessError:
            pytest.fail(f"Agent failed on inputs: {seq1}, {seq2}")

        assert agent_out == oracle_out, f"Mismatch on inputs: '{seq1}', '{seq2}'. Oracle: {oracle_out}, Agent: {agent_out}"


def test_rebuild_rust_project_and_run_without_oracle():
    cargo_toml = os.path.join(PROJECT_PATH, "Cargo.toml")
    main_rs = os.path.join(PROJECT_PATH, "src", "main.rs")
    assert os.path.isfile(cargo_toml), "Rust project is missing Cargo.toml"
    assert os.path.isfile(main_rs), "Rust project is missing src/main.rs"

    oracle_hash = sha256(ORACLE_PATH)
    protected = tempfile.mkdtemp(prefix="hidden-oracle-")
    os.chmod(protected, 0o700)
    hidden_oracle = os.path.join(protected, "seq_align_scorer")
    os.replace(ORACLE_PATH, hidden_oracle)

    try:
        shutil.rmtree(os.path.join(PROJECT_PATH, "target"), ignore_errors=True)
        build = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "cargo", "build", "--release"],
            cwd=PROJECT_PATH,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert build.returncode == 0, "Rust project failed a clean release build with the oracle unavailable:\n" + build.stdout + build.stderr
        assert os.path.isfile(AGENT_PATH) and os.access(AGENT_PATH, os.X_OK), "Clean build did not produce the required executable"
        with open(AGENT_PATH, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Clean build output is not an ELF executable"
        assert sha256(AGENT_PATH) != oracle_hash, "Clean build reproduced the legacy executable byte-for-byte"

        user = pwd.getpwnam("user")
        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        random.seed(42)
        chars = ['A', 'C', 'G', 'T']
        for i in range(1000):
            len1 = random.randint(5, 60)
            len2 = random.randint(5, 60)
            seq1 = "".join(random.choices(chars, k=len1))
            seq2 = "".join(random.choices(chars, k=len2))
            try:
                output = subprocess.check_output(
                    [AGENT_PATH, seq1, seq2],
                    text=True,
                    timeout=5,
                    preexec_fn=demote,
                ).strip()
            except subprocess.CalledProcessError:
                pytest.fail(f"Rebuilt agent failed without oracle on inputs: {seq1}, {seq2}")
            assert output == expected_score(seq1, seq2), (
                f"Rebuilt agent mismatch without oracle on '{seq1}', '{seq2}': expected {expected_score(seq1, seq2)}, got {output}"
            )
    finally:
        if os.path.exists(hidden_oracle):
            os.replace(hidden_oracle, ORACLE_PATH)
        os.rmdir(protected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
