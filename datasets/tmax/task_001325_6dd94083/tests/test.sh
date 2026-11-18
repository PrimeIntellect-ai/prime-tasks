#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import shutil
import subprocess
import sys
import tempfile

import pytest

PROJECT_DIR = "/home/user/project"


def test_libchecksum_so_built():
    """Verify that libchecksum.so was built successfully."""
    so_path = os.path.join(PROJECT_DIR, "libchecksum.so")
    assert os.path.isfile(so_path), f"{so_path} does not exist. Did you run make and fix the Makefile?"

    try:
        lib = ctypes.CDLL(so_path)
    except OSError as e:
        pytest.fail(f"Failed to load {so_path}. Is it a valid shared library compiled with -fPIC and -shared? Error: {e}")

    assert hasattr(lib, "compute_checksum"), "compute_checksum function not found in libchecksum.so"


def test_protobuf_compiled():
    """Verify that message.proto was compiled to Python."""
    pb2_path = os.path.join(PROJECT_DIR, "message_pb2.py")
    assert os.path.isfile(pb2_path), f"{pb2_path} does not exist. Did you compile message.proto with protoc?"


def test_run_test_script_exists():
    """Verify that the test script run_test.py exists."""
    script_path = os.path.join(PROJECT_DIR, "run_test.py")
    assert os.path.isfile(script_path), f"{script_path} does not exist."


def test_checksum_output():
    """Verify that checksum_out.txt exists and contains the correct value."""
    out_path = os.path.join(PROJECT_DIR, "checksum_out.txt")
    assert os.path.isfile(out_path), f"{out_path} does not exist. Did your script write the output?"

    with open(out_path, "r") as f:
        content = f.read().strip()

    assert content == "3211", f"Expected checksum '3211', but found '{content}' in {out_path}."


def test_makefile_rebuilds_library():
    """Require the submitted Makefile to rebuild the shared library from scratch."""
    for name in ("libchecksum.so", "checksum.o"):
        path = os.path.join(PROJECT_DIR, name)
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["make"], cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}"

    so_path = os.path.join(PROJECT_DIR, "libchecksum.so")
    assert os.path.isfile(so_path), "make did not produce libchecksum.so"
    lib = ctypes.CDLL(so_path)
    assert hasattr(lib, "compute_checksum")


def _reference_checksum(data):
    value = 0
    for i, byte in enumerate(data):
        value ^= byte << (i % 8)
    return value & 0xffffffff


def test_library_computes_checksums():
    """Exercise the rebuilt implementation on verifier-selected inputs."""
    lib = ctypes.CDLL(os.path.join(PROJECT_DIR, "libchecksum.so"))
    fn = lib.compute_checksum
    fn.argtypes = [ctypes.c_char_p, ctypes.c_int]
    fn.restype = ctypes.c_uint32

    rng = random.SystemRandom()
    payloads = [b"", b"abc", b"SystemsDebug"]
    for _ in range(5):
        payloads.append(bytes(rng.randrange(1, 128) for _ in range(rng.randrange(1, 80))))

    for payload in payloads:
        assert fn(payload, len(payload)) == _reference_checksum(payload)


def test_generated_protobuf_schema_and_serialization():
    """Ensure message_pb2 is importable and implements the requested Record schema."""
    sys.path.insert(0, PROJECT_DIR)
    try:
        sys.modules.pop("message_pb2", None)
        import message_pb2

        descriptor = message_pb2.Record.DESCRIPTOR
        fields = [(f.name, f.number, f.type) for f in descriptor.fields]
        assert fields == [("id", 1, 5), ("name", 2, 9)]

        record = message_pb2.Record()
        record.id = 42
        record.name = "SystemsDebug"
        assert record.SerializeToString() == b"\x08\x2a\x12\x0cSystemsDebug"
    finally:
        if sys.path and sys.path[0] == PROJECT_DIR:
            sys.path.pop(0)


def _type_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def test_run_test_declares_ctypes_signature():
    """Check the explicitly required ctypes argument and return declarations."""
    script_path = os.path.join(PROJECT_DIR, "run_test.py")
    with open(script_path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=script_path)

    argtypes_ok = False
    restype_ok = False
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        for target in targets:
            if isinstance(target, ast.Attribute) and target.attr == "argtypes":
                if isinstance(value, (ast.List, ast.Tuple)):
                    names = [_type_name(item) for item in value.elts]
                    argtypes_ok = names == ["c_char_p", "c_int"]
            if isinstance(target, ast.Attribute) and target.attr == "restype":
                restype_ok = _type_name(value) == "c_uint32"

    assert argtypes_ok, "run_test.py must set compute_checksum.argtypes to [ctypes.c_char_p, ctypes.c_int]"
    assert restype_ok, "run_test.py must set compute_checksum.restype to ctypes.c_uint32"


def test_run_test_executes_required_ctypes_flow():
    """Run the submitted script against a fresh probe library.

    The probe accepts only the required serialized Record and returns an unpredictable
    unsigned value, so a script that merely writes the known checksum cannot pass.
    """
    script_path = os.path.join(PROJECT_DIR, "run_test.py")
    so_path = os.path.join(PROJECT_DIR, "libchecksum.so")
    out_path = os.path.join(PROJECT_DIR, "checksum_out.txt")
    expected_bytes = b"\x08\x2a\x12\x0cSystemsDebug"

    rng = random.SystemRandom()
    token = 0x80000000 | rng.getrandbits(31)
    while token in (3211, 0x13579BDF):
        token = 0x80000000 | rng.getrandbits(31)

    byte_list = ", ".join(str(b) for b in expected_bytes)
    source = f'''#include <stdint.h>
#include <stddef.h>
uint32_t compute_checksum(const char *data, int len) {{
    static const unsigned char expected[] = {{{byte_list}}};
    if (len != (int)sizeof(expected)) return UINT32_C(0x13579BDF);
    for (int i = 0; i < len; ++i) {{
        if ((unsigned char)data[i] != expected[i]) return UINT32_C(0x13579BDF);
    }}
    return UINT32_C({token});
}}
'''

    with tempfile.TemporaryDirectory() as td:
        probe_c = os.path.join(td, "probe.c")
        probe_so = os.path.join(td, "libchecksum.so")
        backup_so = os.path.join(td, "original.so")
        with open(probe_c, "w", encoding="utf-8") as f:
            f.write(source)
        build = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert build.returncode == 0, f"Failed to build verifier probe:\n{build.stdout}"

        shutil.copy2(so_path, backup_so)
        old_output = None
        if os.path.exists(out_path):
            with open(out_path, "rb") as f:
                old_output = f.read()

        try:
            shutil.copy2(probe_so, so_path)
            if os.path.exists(out_path):
                os.remove(out_path)

            result = subprocess.run(
                [sys.executable, script_path], cwd=PROJECT_DIR, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
            )
            assert result.returncode == 0, f"run_test.py failed:\n{result.stdout}"
            assert os.path.isfile(out_path), "run_test.py did not create checksum_out.txt"
            with open(out_path, "r", encoding="utf-8") as f:
                actual = f.read().strip()
            assert actual == str(token), (
                "run_test.py did not serialize the required Record and write the "
                "uint32_t result returned by compute_checksum"
            )
        finally:
            shutil.copy2(backup_so, so_path)
            if old_output is None:
                if os.path.exists(out_path):
                    os.remove(out_path)
            else:
                with open(out_path, "wb") as f:
                    f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
