#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY = "/home/user/token_filter"
SOURCE = "/home/user/token_filter.c"


def run_filter(binary, args):
    try:
        return subprocess.run(
            [binary] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary} timed out")


def write_token(directory, contents):
    fd, path = tempfile.mkstemp(prefix="case_", suffix=".dat", dir=directory)
    with os.fdopen(fd, "w", encoding="ascii") as f:
        f.write(contents)
    return path


def make_token(payload, seed):
    encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
    signature = hashlib.sha256((seed + encoded).encode("ascii")).hexdigest()
    return f"{encoded}.{signature}"


@pytest.fixture(scope="module")
def binaries():
    assert os.path.isfile(SOURCE), f"C source is missing: {SOURCE}"
    assert os.path.isfile(BINARY), f"Compiled binary is missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary is not executable: {BINARY}"

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "token_filter must be a compiled ELF executable"

    build_dir = tempfile.mkdtemp(prefix="filter_build_")
    rebuilt = os.path.join(build_dir, "rebuilt_filter")
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", rebuilt,
         "-lssl", "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"token_filter.c does not compile:\n{result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    return [BINARY, rebuilt]


def test_token_filter_exists_and_executable(binaries):
    assert os.path.isfile(BINARY), f"Compiled binary is missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary is not executable: {BINARY}"


def test_adversarial_corpus_classification(binaries):
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory is missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory is missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_failures = []
    for path in clean_files:
        if run_filter(BINARY, [path]) != 0:
            clean_failures.append(os.path.basename(path))

    evil_failures = []
    for path in evil_files:
        if run_filter(BINARY, [path]) != 1:
            evil_failures.append(os.path.basename(path))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
                      + ", ".join(evil_failures))
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
                      + ", ".join(clean_failures))
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_unseen_tokens_and_argument_handling(binaries):
    with open("/app/auth_logs.txt", "r", encoding="utf-8") as f:
        logs = f.read()
    match = re.search(r"Rotation salt for today is\s+(\S+)", logs, re.IGNORECASE)
    assert match, "Rotation Salt is missing from auth_logs.txt"
    salt = match.group(1)

    old_passcode = "ab7399"
    new_seed = hashlib.sha256((old_passcode + salt).encode("utf-8")).hexdigest()

    work_dir = tempfile.mkdtemp(prefix="token_validation_")
    nonce = secrets.token_hex(16)
    safe_payloads = [
        f"account:{nonce}",
        f"message=ordinary-{secrets.token_hex(23)}",
        f"roles:user,reader;id={secrets.randbelow(10**9)}",
    ]

    cases = []
    for payload in safe_payloads:
        cases.append((make_token(payload, new_seed), 0, "valid new-seed token"))

    malicious_payloads = [
        f"prefix-{nonce}<ScRiPt>alert(1)</sCrIpT>",
        f"url=JaVaScRiPt:alert({secrets.randbelow(1000)})",
        f"image=x ONLOAD=alert({secrets.randbelow(1000)})",
    ]
    for payload in malicious_payloads:
        cases.append((make_token(payload, new_seed), 1, "malicious payload"))

    legacy_payload = f"legacy:{secrets.token_hex(13)}"
    cases.append((make_token(legacy_payload, old_passcode), 1, "legacy signature"))

    forged_payload = f"forged:{secrets.token_hex(13)}"
    cases.append((make_token(forged_payload, secrets.token_hex(32)), 1, "wrong signature"))

    encoded = base64.b64encode(f"case:{nonce}".encode()).decode("ascii")
    valid_sig = hashlib.sha256((new_seed + encoded).encode("ascii")).hexdigest()
    cases.extend([
        (f"{encoded}.{valid_sig.upper()}", 1, "uppercase signature"),
        (f"{encoded}.{valid_sig[:-1]}", 1, "short signature"),
        (f"{encoded}.{valid_sig}.extra", 1, "extra token component"),
        (encoded, 1, "missing signature"),
    ])

    invalid_b64 = "@@@@"
    invalid_b64_sig = hashlib.sha256((new_seed + invalid_b64).encode("ascii")).hexdigest()
    cases.append((f"{invalid_b64}.{invalid_b64_sig}", 1, "invalid base64"))

    paths = []
    for contents, expected, description in cases:
        path = write_token(work_dir, contents)
        paths.append((path, expected, description))

    for binary in binaries:
        for path, expected, description in paths:
            actual = run_filter(binary, [path])
            assert actual == expected, (
                f"{binary} returned {actual}, expected {expected} for {description}"
            )

        assert run_filter(binary, []) == 1, f"{binary} must reject zero arguments"
        assert run_filter(binary, [paths[0][0], paths[1][0]]) == 1, (
            f"{binary} must reject more than one argument"
        )
        missing = os.path.join(work_dir, "does_not_exist_" + secrets.token_hex(8))
        assert run_filter(binary, [missing]) == 1, f"{binary} must reject unreadable files"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
