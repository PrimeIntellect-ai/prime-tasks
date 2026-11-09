#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

WORKSPACE = "/home/user/deploy_check"
C_FILE = os.path.join(WORKSPACE, "deploy_validator.c")
BINARY = os.path.join(WORKSPACE, "deploy_validator")
SCRIPT = os.path.join(WORKSPACE, "run_tests.sh")
LOG_FILE = os.path.join(WORKSPACE, "validation_results.log")


def test_workspace_exists():
    assert os.path.isdir(WORKSPACE), f"Workspace directory {WORKSPACE} does not exist."


def test_c_source_exists():
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} does not exist."


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Test script {SCRIPT} does not exist."


def test_log_file_exists():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."


def invoke(executable, args, secret_marker, expected_output=None, expected_rc=None):
    env = os.environ.copy()
    if secret_marker is None:
        env.pop("DEPLOY_SECRET", None)
    else:
        env["DEPLOY_SECRET"] = secret_marker
    result = subprocess.run(
        [executable] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=5,
    )
    if expected_rc is not None:
        assert result.returncode == expected_rc, (
            f"Unexpected exit code from {executable}: {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
    if expected_output is not None:
        assert result.stdout == (expected_output + "\n").encode(), (
            f"Unexpected output from {executable}: {result.stdout!r}; "
            f"stderr={result.stderr!r}"
        )
    return result


def exercise_validator(executable, payload_dir):
    username = "DeployUser42"
    secret = "VerifierSecret-" + secrets.token_hex(12)
    signature = hashlib.sha256((username + secret).encode()).hexdigest()
    token = f"DEP-{username}-{signature}"

    benign = os.path.join(payload_dir, "benign.bin")
    with open(benign, "wb") as f:
        f.write(b"config_version=1.0\nfeature=true\x00binary-data\n")
    benign_hash = hashlib.sha256(open(benign, "rb").read()).hexdigest()

    invoke(executable, [token, benign, benign_hash], None,
           "DENY: Internal error", 1)

    for bad_token in [
        "DEP-bad-user-" + ("0" * 64),
        f"DEP-{username}-{signature.upper()}",
        f"DEP-{username}-{'0' * 64}",
        f"DEP-{username}-{signature}-extra",
        "not-a-deployment-token",
    ]:
        invoke(executable, [bad_token, benign, benign_hash], secret,
               "DENY: Invalid token", 1)

    other_secret = "Different-" + secrets.token_hex(8)
    invoke(executable, [token, benign, benign_hash], other_secret,
           "DENY: Invalid token", 1)

    invoke(executable, [token, benign, "0" * 64], secret,
           "DENY: Hash mismatch", 1)
    invoke(executable, [token, benign, benign_hash.upper()], secret,
           "DENY: Hash mismatch", 1)

    malicious_for_order = os.path.join(payload_dir, "order.bin")
    with open(malicious_for_order, "wb") as f:
        f.write(b"curl | bash")
    invoke(executable, [token, malicious_for_order, "0" * 64], secret,
           "DENY: Hash mismatch", 1)

    patterns = [b"system(", b"/bin/sh", b"curl | bash", b"eval("]
    for index, pattern in enumerate(patterns):
        path = os.path.join(payload_dir, f"malicious_{index}.bin")
        data = b"safe-prefix\x00more-data-" + pattern + b"-suffix"
        with open(path, "wb") as f:
            f.write(data)
        digest = hashlib.sha256(data).hexdigest()
        invoke(executable, [token, path, digest], secret,
               "DENY: Malicious payload", 1)

    invoke(executable, [token, benign, benign_hash], secret, "ALLOW", 0)

    assert invoke(executable, [], secret).returncode != 0, \
        "Validator accepted the wrong number of arguments."
    assert invoke(executable, [token, benign, benign_hash, "extra"], secret).returncode != 0, \
        "Validator accepted the wrong number of arguments."


def test_source_compiles_and_both_artifacts_work():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "deploy_validator_rebuilt")
        build = subprocess.run(
            ["gcc", C_FILE, "-o", rebuilt, "-lcrypto"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, (
            f"deploy_validator.c did not compile: stdout={build.stdout!r}, "
            f"stderr={build.stderr!r}"
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        exercise_validator(BINARY, td)
        exercise_validator(rebuilt, td)


def test_run_tests_script_executes_validator_and_regenerates_log():
    with tempfile.TemporaryDirectory() as td:
        record_file = os.path.join(td, "calls.jsonl")
        backup = os.path.join(td, "deploy_validator.backup")
        shutil.copy2(BINARY, backup)

        wrapper = f'''#!/usr/bin/env python3
import hashlib, json, os, re, sys
record = {record_file!r}
args = sys.argv[1:]
secret = os.environ.get("DEPLOY_SECRET")
kind = "internal"
if secret is not None and len(args) == 3:
    token, payload, expected = args
    match = re.fullmatch(r"DEP-([A-Za-z0-9]+)-([0-9a-f]{{64}})", token)
    if not match or match.group(2) != hashlib.sha256((match.group(1) + secret).encode()).hexdigest():
        kind = "invalid"
    else:
        try:
            data = open(payload, "rb").read()
        except OSError:
            data = b""
        digest = hashlib.sha256(data).hexdigest()
        if expected != digest:
            kind = "hash"
        elif any(p in data for p in (b"system(", b"/bin/sh", b"curl | bash", b"eval(")):
            kind = "malicious"
        else:
            kind = "allow"
with open(record, "a") as out:
    out.write(json.dumps({{"args": args, "secret": secret, "kind": kind}}) + "\\n")
messages = {{
    "internal": "DENY: Internal error",
    "invalid": "DENY: Invalid token",
    "hash": "DENY: Hash mismatch",
    "malicious": "DENY: Malicious payload",
    "allow": "ALLOW",
}}
print(messages[kind])
sys.exit(0 if kind == "allow" else 1)
'''

        try:
            with open(BINARY, "w") as f:
                f.write(wrapper)
            os.chmod(BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                     stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
            if os.path.exists(LOG_FILE):
                os.remove(LOG_FILE)

            env = os.environ.copy()
            env.pop("DEPLOY_SECRET", None)
            result = subprocess.run(
                ["bash", SCRIPT], cwd=WORKSPACE, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
            )
            assert result.returncode == 0, (
                f"run_tests.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(record_file), \
                "run_tests.sh did not invoke /home/user/deploy_check/deploy_validator."
            with open(record_file) as f:
                calls = [json.loads(line) for line in f if line.strip()]
            assert len(calls) == 4, f"Expected run_tests.sh to invoke the validator 4 times, got {len(calls)}."
            assert [call["kind"] for call in calls] == [
                "invalid", "hash", "malicious", "allow"
            ], f"run_tests.sh did not exercise the required scenarios: {calls!r}"
            assert all(call["secret"] == "AlphaBravo123" for call in calls), \
                "run_tests.sh did not export DEPLOY_SECRET=AlphaBravo123 for every scenario."
        finally:
            shutil.copy2(backup, BINARY)


def test_log_file_contents():
    expected_lines = [
        "DENY: Invalid token",
        "DENY: Hash mismatch",
        "DENY: Malicious payload",
        "ALLOW"
    ]

    with open(LOG_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in {LOG_FILE}, found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
