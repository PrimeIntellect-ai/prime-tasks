#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import difflib
import json
import os
import subprocess
import sys
import uuid

import pytest

PROJECT = "/home/user/project"
C_LIB = f"{PROJECT}/clib/libc_lib.so"
RUST_DIR = f"{PROJECT}/rust_wrapper"
RUST_LIB = f"{RUST_DIR}/target/release/librust_wrapper.so"
SCRIPT = f"{PROJECT}/test_ffi.py"
EXPECTED = f"{PROJECT}/expected.txt"
DIFF = f"{PROJECT}/diff.txt"


def ffi_env(extra=None):
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = f"{PROJECT}/clib" + (f":{old}" if old else "")
    if extra:
        env.update(extra)
    return env


def test_c_lib_compiled():
    assert os.path.exists(C_LIB), f"C library {C_LIB} was not compiled or is missing."
    with open(C_LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"C library {C_LIB} is not an ELF shared library."


def test_rust_lib_compiled():
    assert os.path.exists(RUST_LIB), f"Rust library {RUST_LIB} was not compiled or is missing."
    with open(RUST_LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Rust library {RUST_LIB} is not an ELF shared library."


def test_rust_build_script_fixed():
    build_rs_path = f"{RUST_DIR}/build.rs"
    assert os.path.exists(build_rs_path), f"File {build_rs_path} is missing."
    with open(build_rs_path, "r") as f:
        content = f.read()
    assert "cargo:rustc-link-search=" in content, "build.rs does not contain the necessary 'cargo:rustc-link-search' directive to fix the linking issue."


def test_rust_lib_fixed():
    lib_rs_path = f"{RUST_DIR}/src/lib.rs"
    assert os.path.exists(lib_rs_path), f"File {lib_rs_path} is missing."
    with open(lib_rs_path, "r") as f:
        content = f.read()
    assert "into_raw" in content, "lib.rs does not seem to fix the borrow checker bug (missing 'into_raw()')."


def test_release_build_and_ffi_behavior():
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_DIR,
        env=ffi_env(),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )

    probe = r'''
import ctypes
c = ctypes.CDLL("/home/user/project/clib/libc_lib.so")
c.get_c_message.argtypes = []
c.get_c_message.restype = ctypes.c_void_p
c.free_c_message.argtypes = [ctypes.c_void_p]
p = c.get_c_message()
assert p
try:
    assert ctypes.string_at(p).decode("utf-8") == "Hello from C"
finally:
    c.free_c_message(p)

rust = ctypes.CDLL("/home/user/project/rust_wrapper/target/release/librust_wrapper.so")
rust.get_combined_message.argtypes = []
rust.get_combined_message.restype = ctypes.c_char_p
for _ in range(3):
    result = rust.get_combined_message()
    assert result is not None
    assert result.decode("utf-8") == "Hello from C and Rust!"
'''
    subprocess.run(
        [sys.executable, "-c", probe],
        env=ffi_env(),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_python_script_exists():
    assert os.path.exists(SCRIPT), f"Python test script {SCRIPT} is missing."


def test_python_script_structure_and_execution():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imports_ctypes = False
    imports_difflib = False
    imports_mock = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = {alias.name for alias in node.names}
            imports_ctypes |= "ctypes" in names
            imports_difflib |= "difflib" in names
            imports_mock |= "unittest.mock" in names
        elif isinstance(node, ast.ImportFrom):
            imports_ctypes |= node.module == "ctypes"
            imports_difflib |= node.module == "difflib"
            imports_mock |= node.module == "unittest.mock" or (
                node.module == "unittest" and any(alias.name == "mock" for alias in node.names)
            )

    assert imports_ctypes, "test_ffi.py must use ctypes."
    assert imports_difflib, "test_ffi.py must use difflib."
    assert imports_mock, "test_ffi.py must use unittest.mock."
    assert "get_combined_message" in source, "test_ffi.py does not call get_combined_message."
    assert any(isinstance(n, ast.Attribute) and n.attr == "decode" for n in ast.walk(tree)), \
        "test_ffi.py does not decode the returned bytes."

    original_expected = open(EXPECTED, "rb").read()
    token = "Verifier-" + uuid.uuid4().hex
    changed_expected = ["Apple", token, "Zebra"]
    capture = f"/tmp/diff_capture_{uuid.uuid4().hex}.json"
    hook_dir = f"/tmp/ffi_hook_{uuid.uuid4().hex}"
    os.mkdir(hook_dir)
    hook = f'''\
import difflib as _difflib
import json as _json
_real_unified_diff = _difflib.unified_diff
def _recording_unified_diff(a, b, *args, **kwargs):
    a = list(a)
    b = list(b)
    with open({capture!r}, "w", encoding="utf-8") as f:
        _json.dump({{"a": a, "b": b}}, f)
    return _real_unified_diff(a, b, *args, **kwargs)
_difflib.unified_diff = _recording_unified_diff
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    try:
        with open(EXPECTED, "w", encoding="utf-8") as f:
            f.write("\n".join(changed_expected) + "\n")
        if os.path.exists(DIFF):
            os.remove(DIFF)

        subprocess.run(
            [sys.executable, SCRIPT],
            cwd=PROJECT,
            env=ffi_env({"PYTHONPATH": hook_dir}),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        assert os.path.exists(capture), "test_ffi.py did not call difflib.unified_diff."
        with open(capture, "r", encoding="utf-8") as f:
            captured = json.load(f)

        actual_lines = [
            "Apple\n",
            "Hello from C and Rust!\n",
            "Mango\n",
            "Zebra\n",
        ]
        changed_lines = [line + "\n" for line in changed_expected]
        assert {tuple(captured["a"]), tuple(captured["b"])} == {
            tuple(actual_lines), tuple(changed_lines)
        }, "The diff was not generated from the FFI/mock merged sorted list and expected.txt."
        assert os.path.exists(DIFF), "Executing test_ffi.py did not create diff.txt."
        assert open(DIFF, "r", encoding="utf-8").read().strip(), \
            "test_ffi.py incorrectly produced an empty diff for differing input."
    finally:
        with open(EXPECTED, "wb") as f:
            f.write(original_expected)
        if os.path.exists(capture):
            os.remove(capture)

    if os.path.exists(DIFF):
        os.remove(DIFF)
    subprocess.run(
        [sys.executable, SCRIPT],
        cwd=PROJECT,
        env=ffi_env(),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_diff_output_correct():
    assert os.path.exists(DIFF), f"Diff output file {DIFF} is missing."
    with open(DIFF, "r") as f:
        diff_content = f.read()
    assert diff_content.strip() == "", "Diff output should be empty because the merged and sorted list should match expected.txt exactly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
