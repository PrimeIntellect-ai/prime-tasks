#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

LIB_PATH = "/home/user/src/libsession.so"
FIXTURE_PATH = "/home/user/test_sec.py"
LOG_PATH = "/home/user/result.log"
EXPECTED_LOG = "user_id: 42, is_admin: 1"
MALICIOUS_PAYLOAD = "42,administratoooooooooooooooooooooooooooooooooooor,1"


def run_fixture():
    result = subprocess.run(
        ["python3", FIXTURE_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"The test fixture failed with return code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def assert_result_log():
    assert os.path.isfile(LOG_PATH), f"The file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_LOG, (
        f"Expected '{EXPECTED_LOG}', but got '{content}'"
    )


def test_fixture_exists_executes_and_calls_library():
    assert os.path.isfile(FIXTURE_PATH), f"The required fixture {FIXTURE_PATH} does not exist."
    assert os.path.isfile(LIB_PATH), f"The compiled library {LIB_PATH} does not exist."

    # First execute the submitted fixture against the submitted library.
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    run_fixture()
    assert_result_log()

    # Execute it again with a behavior-compatible instrumented library. This proves
    # the fixture really loads libsession.so and calls parse_session with the exact
    # required payload, rather than merely writing the expected constant.
    temp_dir = tempfile.mkdtemp(prefix="fixture_probe_")
    backup_path = os.path.join(temp_dir, "libsession.original.so")
    shim_path = os.path.join(temp_dir, "libsession.probe.so")
    marker_path = os.path.join(temp_dir, "called.marker")
    marker_secret = secrets.token_hex(24)
    shim_source = os.path.join(temp_dir, "probe.c")

    source = f'''\
#include <stdio.h>
#include <string.h>

typedef struct {{
    int user_id;
    char username[16];
    int is_admin;
}} Session;

__attribute__((visibility("default")))
int parse_session(const char *payload, Session *out_session) {{
    if (!payload || !out_session || strcmp(payload, {json.dumps(MALICIOUS_PAYLOAD)}) != 0)
        return -9;
    out_session->user_id = 42;
    strncpy(out_session->username, "administratoooo", 15);
    out_session->username[15] = '\\0';
    out_session->is_admin = 1;
    FILE *f = fopen({json.dumps(marker_path)}, "w");
    if (!f)
        return -10;
    fputs({json.dumps(marker_secret)}, f);
    fclose(f);
    return 0;
}}
'''
    with open(shim_source, "w") as f:
        f.write(source)

    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", shim_path, shim_source],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Could not build fixture probe: {build.stderr}"

    os.replace(LIB_PATH, backup_path)
    try:
        shutil.copy2(shim_path, LIB_PATH)
        if os.path.exists(LOG_PATH):
            os.unlink(LOG_PATH)
        run_fixture()
        assert_result_log()
        assert os.path.isfile(marker_path), (
            "The fixture did not call parse_session with the exact required payload."
        )
        with open(marker_path, "r") as f:
            assert f.read() == marker_secret
    finally:
        if os.path.lexists(LIB_PATH):
            os.unlink(LIB_PATH)
        os.replace(backup_path, LIB_PATH)
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_result_log_contents():
    assert_result_log()


def test_libsession_exports_function():
    assert os.path.isfile(LIB_PATH), f"The compiled library {LIB_PATH} does not exist."

    # Check export using nm
    result = subprocess.run(["nm", "-D", LIB_PATH], capture_output=True, text=True)
    assert "parse_session" in result.stdout, "The function 'parse_session' is not exported in libsession.so."


def test_memory_safety_no_segfault():
    # Preserve the original oversized-payload check in an isolated subprocess.
    script = r'''
import ctypes
import sys

class Session(ctypes.Structure):
    _fields_ = [
        ("user_id", ctypes.c_int),
        ("username", ctypes.c_char * 16),
        ("is_admin", ctypes.c_int)
    ]

try:
    lib = ctypes.CDLL("/home/user/src/libsession.so")
    lib.parse_session.argtypes = [ctypes.c_char_p, ctypes.POINTER(Session)]
    lib.parse_session.restype = ctypes.c_int

    sess = Session()
    payload = b"99,superlongusernamewhichdefinitelyexceeds32bytesandwillcrashifstrcpyisused,1"
    res = lib.parse_session(payload, ctypes.byref(sess))

    if sess.user_id == 99 and sess.is_admin == 1:
        sys.exit(0)
    else:
        sys.exit(2)
except Exception:
    sys.exit(1)
'''
    result = subprocess.run(["python3", "-c", script], capture_output=True, timeout=20)
    if result.returncode == -11:
        pytest.fail("The C library segfaulted when parsing a long payload. The buffer overflow is not fixed.")
    elif result.returncode == 1:
        pytest.fail("An exception occurred when calling the C library from Python.")
    elif result.returncode == 2:
        pytest.fail("The C library parsed the long payload without crashing, but the parsed values were incorrect.")
    elif result.returncode != 0:
        pytest.fail(f"The C library test failed with return code {result.returncode}.")


def test_parse_session_varied_and_very_long_payloads():
    # Answers are generated inside the isolated process rather than being a fixed
    # pair of constants. Username checks also ensure the third field is found after
    # an arbitrarily long second field.
    script = r'''
import ctypes
import secrets
import string
import sys

class Session(ctypes.Structure):
    _fields_ = [
        ("user_id", ctypes.c_int),
        ("username", ctypes.c_char * 16),
        ("is_admin", ctypes.c_int),
    ]

lib = ctypes.CDLL("/home/user/src/libsession.so")
lib.parse_session.argtypes = [ctypes.c_char_p, ctypes.POINTER(Session)]
lib.parse_session.restype = ctypes.c_int

alphabet = string.ascii_letters + string.digits
cases = [
    (7, "bob", 0),
    (123456, "exactly15charsX", 17),
    (31415, "Z" * 4096, -3),
    (27182, "Q" * (1024 * 1024), 8),
]
for _ in range(8):
    user_id = secrets.randbelow(1_500_000_000) + 1
    is_admin = secrets.randbelow(20001) - 10000
    length = secrets.randbelow(5000) + 1
    username = "".join(secrets.choice(alphabet) for _ in range(length))
    cases.append((user_id, username, is_admin))

for user_id, username, is_admin in cases:
    payload = f"{user_id},{username},{is_admin}".encode("ascii")
    sess = Session()
    rc = lib.parse_session(payload, ctypes.byref(sess))
    if rc != 0:
        raise AssertionError(f"parse_session returned {rc} for a valid payload")
    if sess.user_id != user_id or sess.is_admin != is_admin:
        raise AssertionError(
            f"wrong parsed integers: got {sess.user_id}, {sess.is_admin}; "
            f"expected {user_id}, {is_admin}"
        )
    expected_username = username.encode("ascii")[:15]
    if sess.username != expected_username:
        raise AssertionError(
            f"wrong username: got {sess.username!r}, expected {expected_username!r}"
        )

# Malformed oversized input must fail cleanly rather than overflow or claim success.
malformed = ("M" * (1024 * 1024)).encode("ascii")
sess = Session()
if lib.parse_session(malformed, ctypes.byref(sess)) == 0:
    raise AssertionError("parse_session accepted a payload with missing fields")
'''
    result = subprocess.run(
        ["python3", "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Varied payload parsing failed with return code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
