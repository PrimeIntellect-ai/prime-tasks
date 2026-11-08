#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import os
import random
import secrets
import subprocess
import tempfile

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SALT = b"OmegaDeltaNineNine"


def run_detector(executable, filepath):
    return subprocess.run(
        [executable, filepath],
        capture_output=True,
        text=True,
        timeout=5,
    )


def assert_classification(executable, filepath, expected_output, expected_code):
    result = run_detector(executable, filepath)
    assert result.returncode == expected_code, (
        f"{executable} returned {result.returncode} for {filepath}; "
        f"expected {expected_code}. stderr: {result.stderr!r}"
    )
    assert result.stdout == expected_output, (
        f"{executable} printed {result.stdout!r} for {filepath}; "
        f"expected {expected_output!r}"
    )


def token_for(url):
    return hmac.new(SALT, url.encode(), hashlib.sha256).hexdigest()


def request_bytes(url=None, token=None):
    headers = ["GET / HTTP/1.1", "Host: example.com"]
    if url is not None:
        headers.append(f"X-Redirect-URL: {url}")
    if token is not None:
        headers.append(f"X-Auth-Token: {token}")
    return ("\r\n".join(headers) + "\r\n\r\n").encode()


def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_PATH), f"Detector executable not found at {DETECTOR_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"Detector path {DETECTOR_PATH} is not a file"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"


def test_source_exists():
    assert os.path.exists(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Source path {SOURCE_PATH} is not a file"


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    failed_files = []
    for filepath in clean_files:
        result = run_detector(DETECTOR_PATH, filepath)
        if result.returncode != 0 or result.stdout != "CLEAN\n":
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (should be CLEAN, exit 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    failed_files = []
    for filepath in evil_files:
        result = run_detector(DETECTOR_PATH, filepath)
        if result.returncode != 1 or result.stdout != "EVIL\n":
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be EVIL, exit 1). Offending files: {', '.join(failed_files)}")


def test_randomized_requests_and_c_source():
    with tempfile.TemporaryDirectory(prefix="verify_") as temp_dir:
        rebuilt = os.path.join(temp_dir, secrets.token_hex(10))
        compile_result = subprocess.run(
            ["gcc", "-O2", SOURCE_PATH, "-o", rebuilt, "-lcrypto"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "detector.c did not compile successfully: " + compile_result.stderr
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        nonce = secrets.token_hex(12)
        trusted_root = f"https://trusted.corp/{nonce}?v={secrets.token_hex(5)}"
        trusted_sub = f"http://{secrets.token_hex(5)}.trusted.corp/{secrets.token_hex(9)}"
        evil_external = f"https://{secrets.token_hex(8)}.example.net/{nonce}"
        evil_suffix = f"https://trusted.corp.{secrets.token_hex(6)}.com/{nonce}"
        evil_prefix = f"http://not-trusted.corp/{secrets.token_hex(7)}"

        bad_token = token_for(trusted_root)
        bad_token = ("0" if bad_token[0] != "0" else "1") + bad_token[1:]

        cases = [
            (request_bytes(trusted_root, token_for(trusted_root)), "CLEAN\n", 0),
            (request_bytes(trusted_sub, token_for(trusted_sub)), "CLEAN\n", 0),
            (request_bytes(trusted_root, bad_token), "EVIL\n", 1),
            (request_bytes(evil_external, token_for(evil_external)), "EVIL\n", 1),
            (request_bytes(evil_suffix, token_for(evil_suffix)), "EVIL\n", 1),
            (request_bytes(evil_prefix, token_for(evil_prefix)), "EVIL\n", 1),
            (request_bytes(trusted_root, None), "EVIL\n", 1),
            (request_bytes(None, token_for(trusted_root)), "EVIL\n", 1),
        ]
        random.SystemRandom().shuffle(cases)

        case_dir = os.path.join(temp_dir, secrets.token_hex(10))
        os.mkdir(case_dir)
        written_cases = []
        for body, expected_output, expected_code in cases:
            path = os.path.join(case_dir, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(body)
            written_cases.append((path, expected_output, expected_code))

        for executable in (DETECTOR_PATH, rebuilt):
            for path, expected_output, expected_code in written_cases:
                assert_classification(executable, path, expected_output, expected_code)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
