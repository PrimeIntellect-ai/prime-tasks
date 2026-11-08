#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_BIN = "/home/user/detector"
DETECTOR_SOURCE = "/home/user/detector.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SECRET = b"SecretKey2023!@#"


def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token(payload, header=None, key=SECRET):
    if header is None:
        header = {"typ": "JWT", "alg": "HS256"}
    header_part = b64url(json.dumps(header, separators=(",", ":")).encode())
    payload_part = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{header_part}.{payload_part}"
    signature = hmac.new(key, signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{b64url(signature)}"


def make_raw_token(header_text, payload_text, key=SECRET):
    header_part = b64url(header_text)
    payload_part = b64url(payload_text)
    signing_input = f"{header_part}.{payload_part}"
    signature = hmac.new(key, signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{b64url(signature)}"


def run_detector(path_args):
    return subprocess.run(
        [DETECTOR_BIN] + list(path_args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def write_token(directory, token):
    path = os.path.join(directory, secrets.token_hex(16) + ".jwt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(token)
    return path


def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_BIN), f"Missing detector binary: {DETECTOR_BIN}"
    assert os.path.isfile(DETECTOR_BIN), f"Not a file: {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"Detector binary is not executable: {DETECTOR_BIN}"


def test_requested_c_artifacts_exist():
    assert os.path.isfile(DETECTOR_SOURCE), f"Missing detector source: {DETECTOR_SOURCE}"
    with open(DETECTOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"


def test_clean_corpus():
    if not os.path.exists(DETECTOR_BIN) or not os.access(DETECTOR_BIN, os.X_OK):
        pytest.skip("Detector binary missing or not executable")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (expected exit code 0). "
                    f"Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    if not os.path.exists(DETECTOR_BIN) or not os.access(DETECTOR_BIN, os.X_OK):
        pytest.skip("Detector binary missing or not executable")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_BIN, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code non-zero, e.g., 1). "
                    f"Offending files: {', '.join(failed_files)}")


def test_novel_randomized_valid_and_invalid_tokens():
    nonce = secrets.token_hex(20)
    with tempfile.TemporaryDirectory(prefix="jwt_detector_") as directory:
        valid_tokens = [
            make_token({"user": "novel-" + nonce, "role": "user"}),
            make_token({"role": "user", "user": nonce, "session": secrets.token_hex(12)},
                       {"alg": "HS256", "typ": "JWT", "kid": secrets.token_hex(4)}),
            make_raw_token(
                '{ "typ" : "JWT", "alg" : "HS256" }',
                json.dumps({"user": nonce, "role": "user", "enabled": True}, indent=1),
            ),
        ]
        for token in valid_tokens:
            path = write_token(directory, token)
            result = run_detector([path])
            assert result.returncode == 0, f"Novel valid token was rejected with {result.returncode}"

        evil_tokens = [
            make_token({"user": nonce, "role": "admin"}),
            make_token({"user": nonce, "role": "user"}, key=b"independent-wrong-key-" + secrets.token_bytes(8)),
            make_token({"user": nonce, "role": "user"})[:-1] + ("A" if make_token({"user": nonce, "role": "user"})[-1] != "A" else "B"),
            make_token({"user": nonce, "role": "user"}, {"alg": "RS256", "typ": "JWT"}),
        ]
        for token in evil_tokens:
            path = write_token(directory, token)
            result = run_detector([path])
            assert result.returncode == 1, f"Novel malicious token returned {result.returncode}, expected 1"


def test_alg_none_case_variations():
    with tempfile.TemporaryDirectory(prefix="jwt_none_") as directory:
        for alg in ("none", "NONE", "None", "nOnE"):
            header = b64url(json.dumps({"typ": "JWT", "alg": alg}, separators=(",", ":")))
            payload = b64url(json.dumps({"user": secrets.token_hex(8), "role": "user"}, separators=(",", ":")))
            for signature in ("", b64url(secrets.token_bytes(32))):
                path = write_token(directory, f"{header}.{payload}.{signature}")
                result = run_detector([path])
                assert result.returncode == 1, f"alg={alg!r} returned {result.returncode}, expected 1"


def test_malformed_inputs_are_rejected():
    malformed = [
        "",
        "not-a-jwt",
        "a.b",
        "a.b.c.d",
        "@@@.e30.signature",
        f"{b64url('{\"alg\":\"HS256\"}')}.***.signature",
        make_raw_token('{"alg":"HS256"', '{"user":"x","role":"user"}'),
        make_raw_token('{"alg":"HS256"}', '{"user":"x","role":'),
        f"{b64url('{\"alg\":\"HS256\"}')}.{b64url('{\"role\":\"user\"}')}.***",
    ]
    with tempfile.TemporaryDirectory(prefix="jwt_malformed_") as directory:
        for token in malformed:
            path = write_token(directory, token)
            result = run_detector([path])
            assert result.returncode == 1, f"Malformed token returned {result.returncode}, expected 1: {token!r}"


def test_argument_count_and_missing_file_handling():
    assert run_detector([]).returncode == 1
    missing = os.path.join(tempfile.gettempdir(), "missing-" + secrets.token_hex(20))
    assert run_detector([missing]).returncode == 1
    with tempfile.TemporaryDirectory(prefix="jwt_args_") as directory:
        first = write_token(directory, make_token({"user": secrets.token_hex(8), "role": "user"}))
        second = write_token(directory, make_token({"user": secrets.token_hex(8), "role": "user"}))
        assert run_detector([first, second]).returncode == 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
