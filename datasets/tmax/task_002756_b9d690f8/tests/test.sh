#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import hashlib
import hmac
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

FILTER_BIN = "/home/user/secure_filter"
FILTER_SOURCE = "/home/user/secure_filter.cpp"
REBUILT_FILTER = "/tmp/secure_filter_rebuilt"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
KEY = b"S3cr3tK3y_Rotat1on_2023_HMAC_STR"


def test_secure_filter_exists_and_executable():
    assert os.path.exists(FILTER_BIN), f"The executable {FILTER_BIN} does not exist. Did you compile your C++ program?"
    assert os.path.isfile(FILTER_BIN), f"{FILTER_BIN} is not a file."
    assert os.access(FILTER_BIN, os.X_OK), f"{FILTER_BIN} is not executable."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled executable."


def run_filter(file_path, executable=FILTER_BIN):
    result = subprocess.run(
        [executable, file_path],
        capture_output=True,
        text=True,
        timeout=2
    )
    return result.stdout.strip()


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    rejected_files = []

    for file_path in clean_files:
        output = run_filter(file_path)
        if output != "ACCEPT":
            rejected_files.append((os.path.basename(file_path), output))

    if rejected_files:
        details = ", ".join([f"{f} (output: {o!r})" for f, o in rejected_files[:5]])
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean files were rejected (or had invalid output). Examples: {details}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    accepted_files = []

    for file_path in evil_files:
        output = run_filter(file_path)
        if output != "REJECT":
            accepted_files.append((os.path.basename(file_path), output))

    if accepted_files:
        details = ", ".join([f"{f} (output: {o!r})" for f, o in accepted_files[:5]])
        pytest.fail(f"{len(accepted_files)} of {len(evil_files)} evil files bypassed the filter (or had invalid output). Examples: {details}")


@pytest.fixture(scope="session")
def rebuilt_filter():
    assert os.path.exists(FILTER_SOURCE), f"The required source file {FILTER_SOURCE} does not exist."
    assert os.path.isfile(FILTER_SOURCE), f"{FILTER_SOURCE} is not a regular file."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", FILTER_SOURCE, "-o", REBUILT_FILTER, "-lssl", "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"The C++ source did not compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REBUILT_FILTER) and os.access(REBUILT_FILTER, os.X_OK)
    return REBUILT_FILTER


def test_cpp_source_exists_and_compiles(rebuilt_filter):
    assert rebuilt_filter == REBUILT_FILTER


def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def encode_json(value):
    return b64url(json.dumps(value).encode())


def signed_token(header, payload):
    header_part = encode_json(header)
    payload_part = encode_json(payload)
    message = f"{header_part}.{payload_part}".encode()
    signature = b64url(hmac.new(KEY, message, hashlib.sha256).digest())
    return f"{header_part}.{payload_part}.{signature}"


def request_for(token=None):
    lines = ["GET /api/data HTTP/1.1", "Host: example.com"]
    if token is not None:
        lines.append(f"Authorization: Bearer {token}")
    return "\r\n".join(lines) + "\r\n\r\n"


def invoke_exact(executable, arguments):
    return subprocess.run(
        [executable] + arguments,
        capture_output=True,
        text=True,
        timeout=2,
    )


def test_generated_tokens_and_malformed_requests(rebuilt_filter):
    cases = []
    for _ in range(5):
        payload = {
            "user": secrets.token_hex(10),
            "nonce": secrets.token_urlsafe(18),
            "counter": secrets.randbelow(1_000_000_000),
        }
        header = {"alg": "HS256", "typ": "PTK"}
        valid = signed_token(header, payload)
        cases.append((request_for(valid), "ACCEPT"))

        hpart, ppart, sigpart = valid.split(".")
        changed_payload = dict(payload)
        changed_payload["counter"] += 1
        cases.append((request_for(f"{hpart}.{encode_json(changed_payload)}.{sigpart}"), "REJECT"))

        wrong_signature = b64url(secrets.token_bytes(32))
        cases.append((request_for(f"{hpart}.{ppart}.{wrong_signature}"), "REJECT"))

        none_header = encode_json({"alg": "none", "typ": "PTK"})
        cases.append((request_for(f"{none_header}.{ppart}."), "REJECT"))
        cases.append((request_for(f"{none_header}.{ppart}.{wrong_signature}"), "REJECT"))
        cases.append((request_for(f"{hpart}.{ppart}"), "REJECT"))

    cases.extend([
        (request_for(None), "REJECT"),
        (request_for("not.a.valid.token"), "REJECT"),
        (request_for(".."), "REJECT"),
        ("GET / HTTP/1.1\r\nHost: example.com\r\nAuthorization: Basic abc\r\n\r\n", "REJECT"),
    ])
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="filter_inputs_") as directory:
        materialized = []
        for content, expected in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "w", newline="") as f:
                f.write(content)
            materialized.append((path, expected))

        for executable in (FILTER_BIN, rebuilt_filter):
            for path, expected in materialized:
                result = invoke_exact(executable, [path])
                assert result.stdout == expected + "\n", (
                    f"{executable} returned invalid output for a generated request: "
                    f"expected {expected!r}, got {result.stdout!r}"
                )


def test_requires_exactly_one_argument(rebuilt_filter):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(request_for(None))
        path = f.name
    try:
        for executable in (FILTER_BIN, rebuilt_filter):
            no_arg = invoke_exact(executable, [])
            assert no_arg.stdout == "REJECT\n"
            extra_arg = invoke_exact(executable, [path, path])
            assert extra_arg.stdout == "REJECT\n"
    finally:
        os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
