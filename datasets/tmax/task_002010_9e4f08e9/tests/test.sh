#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

SCANNER = "/home/user/scanner"
SOURCE = "/home/user/scanner.c"
LEGACY = "/app/legacy_scanner"
HIDDEN = "/test_data/hidden_logs.txt"


def run_as_user(path, input_path):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.check_output(
        [path, input_path],
        text=True,
        timeout=60,
        preexec_fn=demote,
    ).strip().split("\n")


def run_legacy(input_path):
    return subprocess.check_output(
        [LEGACY, input_path], text=True, timeout=60
    ).strip().split("\n")


def make_fresh_logs(path):
    rng = random.SystemRandom()
    lines = []
    for i in range(300):
        token = secrets.token_hex(16)
        kind = rng.choice(["clean", "clean", "sql1", "sql2", "fail"])
        if kind == "sql1":
            payload = f"request {token} uNiOn SeLeCt account,secret FROM vault"
        elif kind == "sql2":
            payload = f"admin {token}; DrOp TaBlE transactions; --"
        else:
            payload = f"ordinary transaction {token} amount={rng.randrange(1, 1000000)}"

        digest = hashlib.md5(payload.encode()).hexdigest()
        if kind == "fail":
            digest = secrets.token_hex(16)
            if digest == hashlib.md5(payload.encode()).hexdigest():
                digest = "0" * 32
        lines.append(f"FRESH{i:05d} | {digest} | {payload}\n")

    # The legacy program ignores malformed and empty records; these ensure the
    # replacement is processing the file rather than printing a fixed table.
    lines.extend(["\n", "malformed record\n", "ONLYID | missing-payload\n"])
    rng.shuffle(lines)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.chmod(path, 0o644)


def test_scanner_executable_exists():
    assert os.path.exists(SCANNER), f"Agent's scanner binary is missing at {SCANNER}"
    assert os.path.isfile(SCANNER), f"{SCANNER} is not a file"
    assert os.access(SCANNER, os.X_OK), f"Agent's scanner at {SCANNER} is not executable"
    assert stat.S_ISREG(os.stat(SCANNER).st_mode), f"{SCANNER} is not a regular file"
    with open(SCANNER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SCANNER} is not a compiled executable"


def test_c_source_exists():
    assert os.path.exists(SOURCE), f"C source is missing at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} is not a regular file"
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty"


def test_scanner_accuracy_and_source_build():
    assert os.path.exists(LEGACY), f"Legacy scanner missing at {LEGACY}"
    assert os.path.exists(HIDDEN), f"Hidden test file missing at {HIDDEN}"

    with open(LEGACY, "rb") as f:
        legacy_bytes = f.read()
    with open(SCANNER, "rb") as f:
        scanner_prefix = f.read(len(legacy_bytes))
    assert scanner_prefix != legacy_bytes, (
        "Agent scanner is a copy of the legacy executable (possibly with data appended)"
    )

    work = tempfile.mkdtemp(prefix="scanner_verify_", dir="/tmp")
    os.chmod(work, 0o755)
    fresh = os.path.join(work, "fresh_logs.txt")
    rebuilt = os.path.join(work, "scanner_from_source")
    make_fresh_logs(fresh)

    # Preserve the original exact oracle comparison on the hidden data and add
    # unpredictable records generated only at verification time.
    legacy_hidden = run_legacy(HIDDEN)
    legacy_fresh = run_legacy(fresh)

    hidden_oracle = os.path.join("/root", ".legacy_scanner_" + secrets.token_hex(16))
    os.replace(LEGACY, hidden_oracle)
    try:
        # Compile the submitted C source while the legacy executable is absent.
        build = subprocess.run(
            ["gcc", "-O3", "-o", rebuilt, SOURCE, "-lcrypto"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert build.returncode == 0, f"scanner.c failed to compile:\n{build.stderr}"
        os.chmod(rebuilt, 0o755)

        try:
            agent_hidden = run_as_user(SCANNER, HIDDEN)
            agent_fresh = run_as_user(SCANNER, fresh)
            source_hidden = run_as_user(rebuilt, HIDDEN)
            source_fresh = run_as_user(rebuilt, fresh)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent's scanner failed to execute: {e}")
        except Exception as e:
            pytest.fail(f"Error running agent's scanner: {e}")
    finally:
        os.replace(hidden_oracle, LEGACY)
        shutil.rmtree(work, ignore_errors=True)

    assert len(agent_hidden) > 0, "Agent's scanner produced no output."
    assert len(agent_hidden) == len(legacy_hidden), (
        f"Output length mismatch: agent produced {len(agent_hidden)} lines, "
        f"expected {len(legacy_hidden)} lines."
    )
    matches = sum(
        1 for a, b in zip(agent_hidden, legacy_hidden) if a.strip() == b.strip()
    )
    accuracy = matches / len(legacy_hidden)
    assert accuracy >= 1.0, (
        f"Accuracy is {accuracy}, expected 1.0. The agent's scanner output does not "
        "perfectly match the legacy scanner."
    )

    assert agent_fresh == legacy_fresh, "Scanner failed verification-time generated cases"
    assert source_hidden == legacy_hidden, "scanner.c does not reproduce the hidden results"
    assert source_fresh == legacy_fresh, "scanner.c failed verification-time generated cases"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
