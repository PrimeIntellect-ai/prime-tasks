#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess

APP_DIR = "/home/user/app"
CPP_FILE = os.path.join(APP_DIR, "rotate_creds.cpp")
CONFIG_FILE = os.path.join(APP_DIR, "config.json")
HASH_FILE = os.path.join(APP_DIR, "config.json.sha256")
NEW_CREDS_FILE = os.path.join(APP_DIR, "new_creds.txt")
BINARY_FILE = os.path.join(APP_DIR, "rotate_creds")


def run_binary(*args):
    return subprocess.run(
        [BINARY_FILE, *args], capture_output=True, timeout=10
    )


def install_config(master_key, valid_hash=True):
    raw = ('{"master_key":"' + master_key + '"}').encode()
    with open(CONFIG_FILE, "wb") as f:
        f.write(raw)
    digest = hashlib.sha256(raw).hexdigest()
    if not valid_hash:
        digest = "0" * 64 if digest != "0" * 64 else "1" * 64
    with open(HASH_FILE, "w") as f:
        f.write(digest + "\n")


def test_complete_implementation():
    # Preserve the original source assertions.
    assert os.path.isfile(CPP_FILE), f"Source file {CPP_FILE} does not exist."
    with open(CPP_FILE, "r") as f:
        source_code = f.read()
    assert "SECCOMP_MODE_STRICT" in source_code, "Source code is missing SECCOMP_MODE_STRICT."
    assert "PR_SET_SECCOMP" in source_code, "Source code is missing PR_SET_SECCOMP."

    # Preserve the original final-state and binary assertions.
    assert os.path.isfile(NEW_CREDS_FILE), f"Expected output file {NEW_CREDS_FILE} does not exist."
    with open(NEW_CREDS_FILE, "r") as f:
        content = f.read().strip()
    assert content == "secR3t_k3Y_991_ROTATED", f"Incorrect credential derived. Found: {content}"

    assert os.path.isfile(BINARY_FILE), f"Compiled binary {BINARY_FILE} does not exist."
    assert os.access(BINARY_FILE, os.X_OK), f"Binary {BINARY_FILE} is not executable."
    result = run_binary()
    assert result.returncode == 0, (
        f"Binary execution failed with return code {result.returncode}. "
        "It may have crashed due to a seccomp violation."
    )

    # Build the submitted source so behavioral checks exercise that artifact.
    build = subprocess.run(
        ["g++", "-O2", "-o", BINARY_FILE, CPP_FILE, "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Compilation failed:\n{build.stdout}\n{build.stderr}"

    # A mismatched hash must terminate without touching the credential output.
    bad_key = "bad_" + secrets.token_hex(16)
    install_config(bad_key, valid_hash=False)
    sentinel = b"DO_NOT_REPLACE_ON_HASH_FAILURE"
    with open(NEW_CREDS_FILE, "wb") as f:
        f.write(sentinel)
    result = run_binary()
    with open(NEW_CREDS_FILE, "rb") as f:
        after = f.read()
    assert after == sentinel, "The output was modified despite an invalid configuration hash."

    # Exercise extraction and derivation with an unpredictable valid key.
    dynamic_key = "key_" + secrets.token_hex(20)
    install_config(dynamic_key, valid_hash=True)
    result = run_binary()
    assert result.returncode == 0, f"Binary failed for a valid dynamic configuration: {result.returncode}"
    with open(NEW_CREDS_FILE, "r") as f:
        content = f.read()
    assert content == dynamic_key + "_ROTATED", (
        "The credential was not derived from the master_key in the verified JSON."
    )

    # Trace another unpredictable run. Require successful strict-seccomp activation,
    # followed by the write of the dynamically derived credential to the output file.
    traced_key = "trace_" + secrets.token_hex(20)
    expected = traced_key + "_ROTATED"
    install_config(traced_key, valid_hash=True)
    trace_file = "/tmp/rotate_creds.strace"
    traced = subprocess.run(
        ["strace", "-f", "-s", "4096", "-yy", "-e", "trace=prctl,write,writev",
         "-o", trace_file, BINARY_FILE],
        capture_output=True,
        timeout=10,
    )
    assert traced.returncode == 0, (
        f"Traced binary failed with return code {traced.returncode}; strict seccomp may have killed it."
    )
    with open(NEW_CREDS_FILE, "r") as f:
        assert f.read() == expected, "Traced run produced the wrong dynamic credential."
    with open(trace_file, "r", errors="replace") as f:
        lines = f.readlines()

    seccomp_indexes = [
        i for i, line in enumerate(lines)
        if "prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT" in line
        and re.search(r"=\s*0\s*$", line.strip())
    ]
    assert seccomp_indexes, "The binary never successfully activated strict seccomp mode."
    activation = seccomp_indexes[-1]
    output_writes = [
        i for i, line in enumerate(lines)
        if i > activation
        and ("write(" in line or "writev(" in line)
        and NEW_CREDS_FILE in line
        and expected in line
    ]
    assert output_writes, (
        "The derived credential was not written to new_creds.txt after strict seccomp activation."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
