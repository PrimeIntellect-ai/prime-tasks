#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import os
import subprocess
import sys
import tempfile

import pytest

WORKSPACE = "/home/user/sec_ws"


def test_setup_py_fixed():
    setup_path = os.path.join(WORKSPACE, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py is missing at {setup_path}"
    with open(setup_path, "r") as f:
        content = f.read()
    assert "fast_auth_ext" not in content, "setup.py still contains the misconfigured module name 'fast_auth_ext'."
    assert "Extension('fast_auth'" in content.replace('"', "'"), "setup.py does not define the correct Extension name 'fast_auth'."


def test_protobuf_compiled():
    pb2_path = os.path.join(WORKSPACE, "auth_pb2.py")
    assert os.path.isfile(pb2_path), f"Compiled protobuf file auth_pb2.py is missing at {pb2_path}. Did you compile it?"


def test_c_extension_fixed():
    c_path = os.path.join(WORKSPACE, "src", "deserializer.c")
    assert os.path.isfile(c_path), f"C extension file missing at {c_path}"
    with open(c_path, "r") as f:
        content = f.read()

    assert "Invalid token length" in content, "C file does not contain the expected error message 'Invalid token length' for the bounds check."
    assert "PyExc_ValueError" in content, "C file does not raise a ValueError for the bounds check."


def test_extension_compiled():
    so_files = glob.glob(os.path.join(WORKSPACE, "fast_auth*.so"))
    assert len(so_files) > 0, "Compiled C extension (fast_auth*.so) not found in the workspace. Did you run setup.py build_ext --inplace?"


def test_result_log():
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"Result log missing at {log_path}. Did you run test_server.py and redirect the output?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SUCCESS_HASH_8F92A1B" in content, f"Expected success hash not found in {log_path}."


def run_checked(command, *, cwd, timeout=60, env=None):
    proc = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert proc.returncode == 0, (
        f"Command failed with exit code {proc.returncode}: {' '.join(command)}\n{proc.stdout}"
    )
    return proc.stdout


def exercise_extension(directory):
    code = r'''
import importlib.machinery
import os
import secrets
import struct
import fast_auth

origin = os.path.realpath(fast_auth.__spec__.origin or "")
base = os.path.realpath(os.getcwd()) + os.sep
assert origin.startswith(base), (origin, base)
assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), origin

for size in (1, 7, 31, 257, 4096):
    body = secrets.token_bytes(size)
    payload = struct.pack(">H", len(body)) + body
    assert fast_auth.parse_token(payload) == body

for actual, claimed in ((0, 1), (1, 2), (5, 60000), (32, 65535)):
    payload = struct.pack(">H", claimed) + secrets.token_bytes(actual)
    try:
        fast_auth.parse_token(payload)
    except ValueError as exc:
        assert str(exc) == "Invalid token length", repr(str(exc))
    else:
        raise AssertionError((actual, claimed, "malformed payload was accepted"))
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = directory
    run_checked([sys.executable, "-I", "-c", code], cwd=directory, timeout=20, env=env)


def test_setup_rebuilds_and_workspace_extension_is_real_and_safe():
    run_checked(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=WORKSPACE,
        timeout=60,
    )
    exercise_extension(WORKSPACE)


def test_submitted_c_source_itself_is_safe():
    source = os.path.join(WORKSPACE, "src", "deserializer.c")
    with tempfile.TemporaryDirectory(prefix="verify_fast_auth_") as tmp:
        setup = os.path.join(tmp, "setup.py")
        with open(setup, "w") as f:
            f.write(
                "from setuptools import setup, Extension\n"
                f"setup(name='verify-fast-auth', ext_modules=[Extension('fast_auth', sources=[{source!r}])])\n"
            )
        run_checked(
            [sys.executable, "setup.py", "build_ext", "--inplace"],
            cwd=tmp,
            timeout=60,
        )
        exercise_extension(tmp)


def test_generated_protobuf_is_usable_and_matches_schema():
    code = r'''
import auth_pb2

msg = auth_pb2.AuthToken(username="verifier-user", role="auditor", expiration=17321)
encoded = msg.SerializeToString()
parsed = auth_pb2.AuthToken()
parsed.ParseFromString(encoded)
assert parsed.username == "verifier-user"
assert parsed.role == "auditor"
assert parsed.expiration == 17321
fields = parsed.DESCRIPTOR.fields_by_name
assert set(fields) == {"username", "role", "expiration"}
assert fields["username"].number == 1
assert fields["role"].number == 2
assert fields["expiration"].number == 3
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = WORKSPACE
    run_checked([sys.executable, "-I", "-c", code], cwd=WORKSPACE, timeout=20, env=env)


def test_provided_websocket_test_passes():
    output = run_checked(
        [sys.executable, "test_server.py"],
        cwd=WORKSPACE,
        timeout=30,
    )
    assert "SUCCESS_HASH_8F92A1B" in output, (
        "test_server.py did not emit the required success hash. Output:\n" + output
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
