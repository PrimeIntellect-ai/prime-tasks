#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/probe_libauth.py
import ctypes
import random
import sys

lib = ctypes.CDLL(sys.argv[1])
verify = lib.verify_token
verify.argtypes = [ctypes.c_char_p]
verify.restype = ctypes.c_int

cases = [
    b"",
    b"ADMIN_TOKEN",
    b"ADMIN_TOKEN_X",
    b"XADMIN_TOKEN",
    b"admin_token",
    b"A" * 15,
    b"A" * 16,
    b"A" * 17,
    b"A" * 50,
    b"A" * 4096,
]
random.seed(20249999)
alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
for length in (1, 2, 10, 11, 12, 14, 15, 16, 31, 127, 1024):
    cases.append(bytes(random.choice(alphabet) for _ in range(length)))

for token in cases:
    expected = 1 if token == b"ADMIN_TOKEN" else 0
    actual = verify(token)
    if actual != expected:
        raise AssertionError(
            f"verify_token returned {actual}, expected {expected} for {token[:80]!r}"
        )
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import struct
import subprocess
import sys

import pytest

APP = "/home/user/app"
LIB_VERSIONED = f"{APP}/build/libauth.so.1.0.1"
LIB_LINK = f"{APP}/build/libauth.so"


def test_libauth_c_patched():
    filepath = f"{APP}/src/libauth.c"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read()

    assert "strncpy" in content, "libauth.c was not patched correctly: missing 'strncpy'."
    assert "strcpy(" not in content, "libauth.c was not patched correctly: 'strcpy' is still present."


def test_shared_library_compiled():
    filepath = LIB_VERSIONED
    assert os.path.isfile(filepath), f"Compiled library {filepath} does not exist."

    with open(filepath, "rb") as f:
        header = f.read(20)

    assert header[:4] == b"\x7fELF", f"File {filepath} is not a valid ELF binary."
    assert len(header) >= 18, "ELF header is truncated."
    byte_order = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert byte_order is not None, "ELF file has an invalid byte-order marker."
    assert struct.unpack(byte_order + "H", header[16:18])[0] == 3, "ELF artifact is not a shared object (ET_DYN)."


def test_shared_library_symlink():
    symlink_path = LIB_LINK
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    expected_target = LIB_VERSIONED

    assert resolved_target == expected_target, f"Symlink {symlink_path} does not point to {expected_target}."


def test_submitted_library_loads_and_behaves_safely():
    for library in (LIB_VERSIONED, LIB_LINK):
        result = subprocess.run(
            [sys.executable, "/tmp/probe_libauth.py", library],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"The shared library could not be loaded or failed behavioral/security tests "
            f"(exit {result.returncode}).\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def test_patched_source_builds_with_required_flags_and_behaves():
    rebuilt = "/tmp/libauth_rebuilt.so"
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", f"{APP}/src/libauth.c", "-o", rebuilt],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"Patched source does not compile with -shared -fPIC:\n{result.stderr}"

    probe = subprocess.run(
        [sys.executable, "/tmp/probe_libauth.py", rebuilt],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert probe.returncode == 0, (
        f"Library rebuilt from patched source failed behavioral/security tests "
        f"(exit {probe.returncode}).\nstdout:\n{probe.stdout}\nstderr:\n{probe.stderr}"
    )


def test_manifest_updated():
    filepath = f"{APP}/manifest.json"
    assert os.path.isfile(filepath), f"Manifest file {filepath} does not exist."

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {filepath} is not valid JSON.")

    assert "components" in data, "manifest.json missing 'components' key."
    assert "libauth" in data["components"], "manifest.json missing 'libauth' component."
    assert data["components"]["libauth"].get("version") == "1.0.1", "libauth version in manifest.json was not updated to '1.0.1'."


def test_update_script_exists():
    filepath = f"{APP}/update_manifest.py"
    assert os.path.isfile(filepath), f"Python script {filepath} does not exist."


def test_update_script_implements_semantic_version_behavior():
    script = f"{APP}/update_manifest.py"
    manifest = f"{APP}/manifest.json"
    assert os.path.isfile(script), f"Python script {script} does not exist."

    with open(manifest, "rb") as f:
        final_manifest = f.read()

    cases = [
        ("0.99.99", "1.0.1"),
        ("1.0.0", "1.0.1"),
        ("1.0.1", "1.0.1"),
        ("1.0.2", "1.0.2"),
        ("1.1.0", "1.1.0"),
        ("2.0.0", "2.0.0"),
    ]

    try:
        for old_version, expected_version in cases:
            fixture = {
                "components": {
                    "web_framework": {"version": "2.1.0"},
                    "libauth": {"version": old_version},
                    "sentinel": {"version": "7.8.9"},
                },
                "preserve_me": "unchanged",
            }
            with open(manifest, "w") as f:
                json.dump(fixture, f, indent=2)

            result = subprocess.run(
                [sys.executable, script],
                cwd=APP,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"update_manifest.py failed for version {old_version}:\n{result.stderr}"
            )

            with open(manifest, "r") as f:
                updated = json.load(f)
            assert updated["components"]["libauth"]["version"] == expected_version, (
                f"For existing version {old_version}, expected {expected_version} but got "
                f"{updated['components']['libauth']['version']}"
            )
            assert updated["components"]["sentinel"]["version"] == "7.8.9"
            assert updated["preserve_me"] == "unchanged"
    finally:
        with open(manifest, "wb") as f:
            f.write(final_manifest)


def test_e2e_test_results():
    filepath = f"{APP}/test_results.log"
    e2e_script = f"{APP}/tests/e2e_test.py"
    assert os.path.isfile(e2e_script), f"E2E test script {e2e_script} does not exist."

    if os.path.lexists(filepath):
        os.unlink(filepath)

    result = subprocess.run(
        [sys.executable, e2e_script],
        cwd=APP,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"E2E test did not execute successfully (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(filepath), f"Test results file {filepath} does not exist. Did you run the e2e test script?"

    with open(filepath, "r") as f:
        content = f.read()

    assert content == "E2E SEC TEST: PASS\n", f"Test results file content is incorrect. Got: {content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
