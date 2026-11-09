#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import secrets
import subprocess


class RecordV1(ctypes.Structure):
    _fields_ = [("id", ctypes.c_int), ("name", ctypes.c_char * 20)]


class RecordV2(ctypes.Structure):
    _fields_ = [("id", ctypes.c_int), ("name", ctypes.c_char * 20), ("score", ctypes.c_float)]


def test_source_files_exist():
    """Verify that the required source files were created."""
    assert os.path.isfile('/home/user/migrate.h'), "/home/user/migrate.h does not exist"
    assert os.path.isfile('/home/user/migrate.c'), "/home/user/migrate.c does not exist"
    assert os.path.isfile('/home/user/test_migrate.py'), "/home/user/test_migrate.py does not exist"


def _load_library(path):
    try:
        lib = ctypes.CDLL(path)
    except Exception as e:
        assert False, f"Failed to load {path} via ctypes: {e}"
    assert hasattr(lib, 'migrate_v1_to_v2'), f"Function migrate_v1_to_v2 not found in {path}"
    lib.migrate_v1_to_v2.argtypes = [ctypes.POINTER(RecordV1), ctypes.POINTER(RecordV2)]
    lib.migrate_v1_to_v2.restype = None
    return lib


def _exercise_library(path):
    lib = _load_library(path)

    # Preserve the original fixed-record assertion.
    in_rec = RecordV1(id=42, name=b"TestName")
    out_rec = RecordV2()
    lib.migrate_v1_to_v2(ctypes.byref(in_rec), ctypes.byref(out_rec))
    assert out_rec.id == 42, f"Expected id 42, got {out_rec.id}"
    assert out_rec.name == b"TestName", f"Expected name b'TestName', got {out_rec.name}"
    assert out_rec.score == 0.0, f"Expected score 0.0, got {out_rec.score}"

    cases = [
        (-(2**31), b""),
        (2**31 - 1, b"A" * 19),
        (0, b"a\x00b"),
        (-1, bytes(range(19))),
    ]
    for _ in range(80):
        ident = int.from_bytes(secrets.token_bytes(4), byteorder='little', signed=True)
        length = secrets.randbelow(20)
        cases.append((ident, secrets.token_bytes(length)))

    for ident, name in cases:
        source = RecordV1()
        source.id = ident
        if name:
            ctypes.memmove(ctypes.addressof(source) + RecordV1.name.offset, name, len(name))
        expected_name = name + b'\x00' * (20 - len(name))

        destination = RecordV2()
        ctypes.memset(ctypes.addressof(destination), 0xA5, ctypes.sizeof(destination))
        lib.migrate_v1_to_v2(ctypes.byref(source), ctypes.byref(destination))

        actual_name = ctypes.string_at(
            ctypes.addressof(destination) + RecordV2.name.offset, 20
        )
        assert destination.id == ident, f"id was not copied for input {ident}"
        assert actual_name == expected_name, "the complete 20-byte name array was not copied"
        assert destination.score == 0.0, "score was not initialized to exactly 0.0"


def test_header_source_compile_and_work():
    """Validate the declared ABI and independently build the submitted C source."""
    probe = r'''
#include <stddef.h>
#include "/home/user/migrate.h"
_Static_assert(sizeof(((struct RecordV1 *)0)->id) == sizeof(int), "RecordV1.id must be int");
_Static_assert(sizeof(((struct RecordV1 *)0)->name) == 20, "RecordV1.name must be char[20]");
_Static_assert(offsetof(struct RecordV1, id) == 0, "bad RecordV1.id offset");
_Static_assert(offsetof(struct RecordV1, name) == sizeof(int), "bad RecordV1.name offset");
_Static_assert(sizeof(((struct RecordV2 *)0)->id) == sizeof(int), "RecordV2.id must be int");
_Static_assert(sizeof(((struct RecordV2 *)0)->name) == 20, "RecordV2.name must be char[20]");
_Static_assert(sizeof(((struct RecordV2 *)0)->score) == sizeof(float), "RecordV2.score must be float");
_Static_assert(offsetof(struct RecordV2, id) == 0, "bad RecordV2.id offset");
_Static_assert(offsetof(struct RecordV2, name) == sizeof(int), "bad RecordV2.name offset");
_Static_assert(offsetof(struct RecordV2, score) == sizeof(int) + 20, "bad RecordV2.score offset");
static void (*migration_signature)(const struct RecordV1 *, struct RecordV2 *) = migrate_v1_to_v2;
int verifier_probe(void) { return migration_signature == 0; }
'''
    probe_path = '/tmp/migrate_abi_probe.c'
    rebuilt_path = '/tmp/verifier_libmigrate.so'
    with open(probe_path, 'w') as f:
        f.write(probe)
    result = subprocess.run(
        ['gcc', '-std=c11', '-fPIC', '-shared', '-Wall', '-Werror',
         '/home/user/migrate.c', probe_path, '-o', rebuilt_path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert result.returncode == 0, f"Header/source failed ABI validation or compilation:\n{result.stdout}"
    _exercise_library(rebuilt_path)


def test_libmigrate_exists_and_works():
    """Verify that libmigrate.so exists, can be loaded, and implements the correct logic."""
    lib_path = '/home/user/libmigrate.so'
    assert os.path.isfile(lib_path), f"{lib_path} does not exist"
    _exercise_library(lib_path)


def test_python_script_uses_required_property_testing():
    path = '/home/user/test_migrate.py'
    with open(path, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as e:
        assert False, f"test_migrate.py is not valid Python: {e}"

    imported = []
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imported.append(node.module or '')
        elif isinstance(node, ast.Call):
            calls.append(node)

    assert any(name == 'ctypes' or name.startswith('ctypes.') for name in imported), \
        "test_migrate.py must import and use ctypes"
    assert any(name == 'hypothesis' or name.startswith('hypothesis.') for name in imported), \
        "test_migrate.py must use Hypothesis"

    def call_leaf(call):
        func = call.func
        if isinstance(func, ast.Name):
            return func.id
        if isinstance(func, ast.Attribute):
            return func.attr
        return ''

    leaves = [call_leaf(call) for call in calls]
    assert 'given' in leaves, "test_migrate.py must define a Hypothesis @given test"
    assert 'integers' in leaves, "Hypothesis integer strategies must generate ids"
    binary_calls = [call for call in calls if call_leaf(call) == 'binary']
    assert binary_calls, "Hypothesis binary strategies must generate names"

    valid_binary_range = False
    for call in binary_calls:
        keywords = {kw.arg: kw.value for kw in call.keywords if kw.arg is not None}
        maximum = keywords.get('max_size')
        minimum = keywords.get('min_size')
        max_ok = isinstance(maximum, ast.Constant) and maximum.value == 19
        min_ok = minimum is None or (isinstance(minimum, ast.Constant) and minimum.value == 0)
        if max_ok and min_ok:
            valid_binary_range = True
    assert valid_binary_range, "name strategy must generate byte strings of length 0 through 19"
    assert 'migrate_v1_to_v2' in source and 'score' in source, \
        "test_migrate.py must exercise the migration function and verify score"


def test_log_file_exists_and_passed():
    """Run the required pytest script and verify that its captured output reports success."""
    log_path = '/home/user/test_result.log'
    try:
        result = subprocess.run(
            ['python3', '-m', 'pytest', '/home/user/test_migrate.py', '-o', 'addopts=', '-rA'],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120,
            cwd='/tmp'
        )
    except subprocess.TimeoutExpired:
        assert False, "The required Hypothesis pytest script timed out"

    with open(log_path, 'w') as f:
        f.write(result.stdout)

    assert os.path.isfile(log_path), f"{log_path} does not exist"
    assert result.returncode == 0, f"The required pytest script failed:\n{result.stdout}"
    with open(log_path, 'r') as f:
        log_content = f.read().lower()
    assert "passed" in log_content or "100%" in log_content, \
        "Tests did not pass according to pytest output in test_result.log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
