#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import shutil
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
RUST_DIR = os.path.join(WORKSPACE_DIR, "rust_part")
C_DIR = os.path.join(WORKSPACE_DIR, "c_part")
RUST_LIB = os.path.join(RUST_DIR, "target", "release", "librust_part.so")
C_LIB = os.path.join(C_DIR, "libcchecksum.so")
PYTHON_SCRIPT = os.path.join(WORKSPACE_DIR, "verify_token.py")
LOG_FILE = os.path.join(WORKSPACE_DIR, "build_artifacts.log")
EXPECTED_CONTENT = "Rust Checksum: 1946\nC Checksum: 2552695574"
TOKEN = b"admin=true&user=alice"


def rust_expected(data):
    return sum(data) & 0xffffffff


def c_expected(data):
    value = 5381
    for byte in data:
        value = ((value * 33) + byte) & 0xffffffff
    return value


def load_function(path, symbol):
    library = ctypes.CDLL(path)
    function = getattr(library, symbol)
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_uint32
    return library, function


def test_rust_lib_built():
    assert os.path.isfile(RUST_LIB), f"Rust shared library not found at {RUST_LIB}. Did 'cargo build --release' succeed?"


def test_c_lib_built():
    assert os.path.isfile(C_LIB), f"C shared library not found at {C_LIB}. Did the Makefile compile it correctly?"


def test_python_script_exists():
    assert os.path.isfile(PYTHON_SCRIPT), f"Python script not found at {PYTHON_SCRIPT}."


def test_rust_source_builds_cleanly():
    with tempfile.TemporaryDirectory() as target:
        result = subprocess.run(
            ["cargo", "build", "--release", "--target-dir", target],
            cwd=RUST_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, "Rust project does not build cleanly:\n" + result.stdout
        built = os.path.join(target, "release", "librust_part.so")
        assert os.path.isfile(built), "Clean Rust build did not produce librust_part.so"


def test_makefile_builds_position_independent_shared_library():
    makefile = os.path.join(C_DIR, "Makefile")
    assert os.path.isfile(makefile), "C Makefile is missing"
    with open(makefile, "r") as handle:
        make_text = handle.read()
    assert re.search(r"-fpic\b", make_text, re.IGNORECASE), "Makefile compilation must use -fPIC"

    with tempfile.TemporaryDirectory() as build_dir:
        shutil.copy2(makefile, os.path.join(build_dir, "Makefile"))
        shutil.copy2(os.path.join(C_DIR, "c_checksum.c"), os.path.join(build_dir, "c_checksum.c"))
        result = subprocess.run(
            ["make"], cwd=build_dir, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=60
        )
        assert result.returncode == 0, "C project does not build cleanly:\n" + result.stdout
        built = os.path.join(build_dir, "libcchecksum.so")
        assert os.path.isfile(built), "Clean C build did not produce libcchecksum.so"
        library, function = load_function(built, "c_checksum")
        assert function(TOKEN) == c_expected(TOKEN)


def test_python_script_loads_and_calls_both_libraries():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    wrapper = r'''
import ctypes
import os
import runpy
import sys

script = sys.argv[1]
calls = []
real_cdll = ctypes.CDLL


def argument_bytes(value):
    if isinstance(value, bytes):
        return value
    if isinstance(value, str):
        return value.encode()
    candidate = getattr(value, "value", None)
    if isinstance(candidate, bytes):
        return candidate
    return None


class FunctionProxy:
    def __init__(self, function, library_name, symbol):
        object.__setattr__(self, "_function", function)
        object.__setattr__(self, "_library_name", library_name)
        object.__setattr__(self, "_symbol", symbol)

    def __call__(self, *args, **kwargs):
        result = self._function(*args, **kwargs)
        first = argument_bytes(args[0]) if args else None
        calls.append((os.path.basename(str(self._library_name)), self._symbol, first))
        return result

    def __getattr__(self, name):
        return getattr(self._function, name)

    def __setattr__(self, name, value):
        if name.startswith("_"):
            object.__setattr__(self, name, value)
        else:
            setattr(self._function, name, value)


class LibraryProxy:
    def __init__(self, library, name):
        object.__setattr__(self, "_library", library)
        object.__setattr__(self, "_library_name", name)
        object.__setattr__(self, "_functions", {})

    def __getattr__(self, name):
        value = getattr(self._library, name)
        if isinstance(value, ctypes._CFuncPtr):
            if name not in self._functions:
                self._functions[name] = FunctionProxy(value, self._library_name, name)
            return self._functions[name]
        return value

    def __setattr__(self, name, value):
        if name.startswith("_"):
            object.__setattr__(self, name, value)
        else:
            setattr(self._library, name, value)


def tracked_cdll(name, *args, **kwargs):
    return LibraryProxy(real_cdll(name, *args, **kwargs), name)


def tracked_load_library(self, name):
    return tracked_cdll(name)


ctypes.CDLL = tracked_cdll
ctypes.LibraryLoader.LoadLibrary = tracked_load_library

try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise

required = {
    ("librust_part.so", "rust_checksum", b"admin=true&user=alice"),
    ("libcchecksum.so", "c_checksum", b"admin=true&user=alice"),
}
missing = required.difference(calls)
if missing:
    raise AssertionError("verify_token.py did not load and call both required functions with the required token; missing: %r" % (missing,))
'''
    wrapper_path = "/tmp/run_verify_token.py"
    with open(wrapper_path, "w") as handle:
        handle.write(wrapper)

    result = subprocess.run(
        ["python3", wrapper_path, PYTHON_SCRIPT], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert result.returncode == 0, "verify_token.py failed or did not use both libraries correctly:\n" + result.stdout
    assert os.path.isfile(LOG_FILE), "verify_token.py did not generate build_artifacts.log"


def test_built_libraries_on_derived_inputs():
    rust_library, rust_function = load_function(RUST_LIB, "rust_checksum")
    c_library, c_function = load_function(C_LIB, "c_checksum")

    inputs = [b"", TOKEN, b"a", b"session=guest"]
    inputs.extend(("probe-" + secrets.token_hex(18)).encode("ascii") for _ in range(12))
    for data in inputs:
        assert rust_function(data) == rust_expected(data), f"rust_checksum returned an incorrect value for {data!r}"
        assert c_function(data) == c_expected(data), f"c_checksum returned an incorrect value for {data!r}"


def test_log_file_content():
    assert os.path.isfile(LOG_FILE), f"Log file not found at {LOG_FILE}."
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_CONTENT, f"Log file content does not match expected.\nExpected:\n{EXPECTED_CONTENT}\n\nGot:\n{content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
