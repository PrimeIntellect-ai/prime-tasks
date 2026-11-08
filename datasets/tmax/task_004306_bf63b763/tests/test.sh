#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import random
import secrets
import stat
import subprocess

import pytest

PROJECT_DIR = "/home/user/project"
SRC_DIR = os.path.join(PROJECT_DIR, "src")
INCLUDE_DIR = os.path.join(PROJECT_DIR, "include")
MAKEFILE_PATH = os.path.join(PROJECT_DIR, "Makefile")
LIB_PATH = os.path.join(PROJECT_DIR, "libhelpers.so")
ROUTER_PATH = os.path.join(PROJECT_DIR, "router.sh")
CLEAN_CORPUS_DIR = "/tests/corpus/clean"
EVIL_CORPUS_DIR = "/tests/corpus/evil"
QUERY_ENGINE = "/app/bin/query_engine"


def make_request(encoded):
    return (
        "POST /query HTTP/1.1\n"
        "Content-Type: application/json\n\n"
        f'{{"payload": "{encoded}"}}\n'
    )


def engine_output(encoded):
    result = subprocess.run(
        [QUERY_ENGINE, encoded], capture_output=True, text=True, check=True
    )
    return result.stdout


def test_c_files_moved_to_src():
    assert os.path.isdir(SRC_DIR), f"Directory {SRC_DIR} is missing"
    c_files = glob.glob(os.path.join(SRC_DIR, "*.c"))
    assert len(c_files) > 0, "No .c files found in src directory"
    assert os.path.isfile(os.path.join(SRC_DIR, "utils.c")), "utils.c was not moved to src/"
    old_c_files = glob.glob(os.path.join(PROJECT_DIR, "*.c"))
    assert len(old_c_files) == 0, ".c files still exist in the project root"


def test_h_files_moved_to_include():
    assert os.path.isdir(INCLUDE_DIR), f"Directory {INCLUDE_DIR} is missing"
    h_files = glob.glob(os.path.join(INCLUDE_DIR, "*.h"))
    assert len(h_files) > 0, "No .h files found in include directory"
    assert os.path.isfile(os.path.join(INCLUDE_DIR, "utils.h")), "utils.h was not moved to include/"
    old_h_files = glob.glob(os.path.join(PROJECT_DIR, "*.h"))
    assert len(old_h_files) == 0, ".h files still exist in the project root"


def test_makefile_builds_shared_library():
    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)

    result = subprocess.run(["make"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"Make failed with error:\n{result.stderr}"
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built by make"

    file_output = subprocess.run(["file", LIB_PATH], capture_output=True, text=True).stdout
    assert "shared object" in file_output, f"{LIB_PATH} is not a valid shared object"


def test_router_is_executable():
    assert os.path.isfile(ROUTER_PATH), f"Router script {ROUTER_PATH} is missing"
    assert os.access(ROUTER_PATH, os.X_OK), f"Router script {ROUTER_PATH} is not executable"


def test_router_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for fpath in clean_files:
        with open(fpath, "r") as f:
            payload = f.read()

        result = subprocess.run([ROUTER_PATH], input=payload, text=True, capture_output=True)
        lines = result.stdout.strip().split("\n")
        encoded = payload.split('"payload": "', 1)[1].split('"', 1)[0]
        expected = "HTTP/1.1 200 OK\n" + engine_output(encoded)

        if (
            len(lines) < 2
            or lines[0].strip() != "HTTP/1.1 200 OK"
            or result.stdout != expected
        ):
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {', '.join(failed_files)}")


def test_router_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for fpath in evil_files:
        with open(fpath, "r") as f:
            payload = f.read()

        result = subprocess.run([ROUTER_PATH], input=payload, text=True, capture_output=True)
        output = result.stdout.strip()

        if output != "HTTP/1.1 400 Bad Request":
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {', '.join(failed_files)}")


def test_router_dynamic_clean_requests_match_engine():
    forbidden = {ord("`"), ord("'"), ord('"'), ord("\\")}
    allowed = bytes(c for c in range(0x20, 0x7f) if c not in forbidden)
    samples = [
        b"dynamic_" + secrets.token_hex(12).encode(),
        b"spaces and $hell; metacharacters | are <printable>",
        allowed,
    ]
    rng = random.SystemRandom()
    for _ in range(10):
        samples.append(bytes(rng.choice(allowed) for _ in range(rng.randint(1, 80))))

    for decoded in samples:
        encoded = base64.b64encode(decoded).decode("ascii")
        result = subprocess.run(
            [ROUTER_PATH], input=make_request(encoded), text=True, capture_output=True
        )
        expected = "HTTP/1.1 200 OK\n" + engine_output(encoded)
        assert result.stdout == expected, f"Incorrect response for clean payload {encoded!r}"


def test_router_rejects_restricted_and_nonprintable_bytes():
    bad_decoded = []
    for value in (ord("`"), ord("'"), ord('"'), ord("\\")):
        bad_decoded.append(b"safe-prefix" + bytes([value]) + b"safe-suffix")
    for value in list(range(0x20)) + list(range(0x7f, 0x100)):
        bad_decoded.append(b"x" + bytes([value]) + b"y")

    for decoded in bad_decoded:
        encoded = base64.b64encode(decoded).decode("ascii")
        result = subprocess.run(
            [ROUTER_PATH], input=make_request(encoded), text=True, capture_output=True
        )
        assert result.stdout in (
            "HTTP/1.1 400 Bad Request",
            "HTTP/1.1 400 Bad Request\n",
        ), f"Payload containing prohibited byte {decoded!r} was not rejected"

    for encoded in ("!!!!", "@@@@", "abcde"):
        result = subprocess.run(
            [ROUTER_PATH], input=make_request(encoded), text=True, capture_output=True
        )
        assert result.stdout in (
            "HTTP/1.1 400 Bad Request",
            "HTTP/1.1 400 Bad Request\n",
        ), f"Malformed base64 payload {encoded!r} was not rejected"


def test_router_invokes_engine_with_original_argument_and_blocks_bad_input():
    original = open(QUERY_ENGINE, "rb").read()
    original_mode = stat.S_IMODE(os.stat(QUERY_ENGINE).st_mode)
    log_path = f"/tmp/router_engine_arg_{secrets.token_hex(10)}"
    token = f"engine-output-{secrets.token_hex(16)}"
    spy = f'''#!/usr/bin/env python3
import pathlib
import sys
pathlib.Path({log_path!r}).write_text(sys.argv[1] if len(sys.argv) > 1 else "<missing>")
print({token!r})
'''

    try:
        with open(QUERY_ENGINE, "w") as f:
            f.write(spy)
        os.chmod(QUERY_ENGINE, 0o755)

        encoded = base64.b64encode(
            ("original-argument-" + secrets.token_hex(18)).encode()
        ).decode("ascii")
        result = subprocess.run(
            [ROUTER_PATH], input=make_request(encoded), text=True, capture_output=True
        )
        assert result.stdout == f"HTTP/1.1 200 OK\n{token}\n"
        assert os.path.isfile(log_path), "query_engine was not invoked"
        assert open(log_path).read() == encoded, "router did not pass the original base64 argument"

        os.remove(log_path)
        bad_encoded = base64.b64encode(b"unsafe`value").decode("ascii")
        result = subprocess.run(
            [ROUTER_PATH], input=make_request(bad_encoded), text=True, capture_output=True
        )
        assert result.stdout in (
            "HTTP/1.1 400 Bad Request",
            "HTTP/1.1 400 Bad Request\n",
        )
        assert not os.path.exists(log_path), "query_engine was invoked for a rejected payload"
    finally:
        with open(QUERY_ENGINE, "wb") as f:
            f.write(original)
        os.chmod(QUERY_ENGINE, original_mode)
        if os.path.exists(log_path):
            os.remove(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
