#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import inspect
import os
import re
import secrets
import string
import subprocess

BASE = "/home/user/release_prep"
CRATE = os.path.join(BASE, "rust_ffi")
SO_PATH = os.path.join(CRATE, "target/release/librust_ffi.so")
PY_PATH = os.path.join(BASE, "test_release.py")


def test_rust_lib_built():
    assert os.path.isfile(SO_PATH), f"Rust shared library not found at {SO_PATH}. Did you build in release mode?"


def test_test_log_exists_and_passed():
    log_path = os.path.join(BASE, "test.log")
    assert os.path.isfile(log_path), f"Test log file not found at {log_path}. Did you redirect pytest output?"

    with open(log_path, "r") as f:
        content = f.read()

    assert re.search(r"1 passed", content), "The test.log does not indicate that 1 test passed."


def test_test_release_py_modified():
    assert os.path.isfile(PY_PATH), f"Python test file missing at {PY_PATH}"

    with open(PY_PATH, "r") as f:
        content = f.read()

    assert "Mock()" not in content, "The Mock object is still present in test_release.py."
    assert "ctypes.CDLL" in content, "ctypes.CDLL is not being used to load the shared library."
    assert "argtypes" in content, "argtypes is not configured for the function."
    assert "restype" in content, "restype is not configured for the function."


def test_rust_code_fixed():
    lib_rs_path = os.path.join(CRATE, "src/lib.rs")
    assert os.path.isfile(lib_rs_path), f"Rust source file missing at {lib_rs_path}"

    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "into_raw" in content, "The Rust code does not appear to use `into_raw` to pass ownership to C safely."


def test_current_rust_source_builds_in_release_mode():
    clean = subprocess.run(
        ["/usr/bin/cargo", "clean"], cwd=CRATE, capture_output=True, text=True
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["/usr/bin/cargo", "build", "--release"],
        cwd=CRATE,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Release build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(SO_PATH), "Release build did not produce librust_ffi.so"
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced .so is not an ELF shared object"


def _random_version():
    alphabet = string.ascii_letters + string.digits + "._-"
    return "v" + "".join(secrets.choice(alphabet) for _ in range(24))


def test_compiled_library_loads_and_handles_derived_inputs():
    lib = ctypes.CDLL(SO_PATH)
    fn = lib.generate_release_tag
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_char_p

    versions = [_random_version() for _ in range(4)]
    for version in versions:
        actual = fn(version.encode("utf-8"))
        expected = ("RELEASE-" + version).encode("utf-8")
        assert actual == expected, f"Unexpected Rust FFI result for {version!r}: {actual!r}"


def test_release_fixture_really_yields_configured_rust_cdll():
    spec = importlib.util.spec_from_file_location("submitted_test_release", PY_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    fixture = getattr(module, "release_lib", None)
    assert fixture is not None, "release_lib fixture is missing"
    assert hasattr(fixture, "_pytestfixturefunction"), "release_lib is not a pytest fixture"

    fixture_body = getattr(fixture, "__wrapped__", fixture)
    produced = fixture_body()
    generator = produced if inspect.isgenerator(produced) else None
    lib = next(generator) if generator is not None else produced

    try:
        assert isinstance(lib, ctypes.CDLL), "release_lib did not provide a real ctypes.CDLL instance"
        loaded_name = os.fspath(lib._name)
        if not os.path.isabs(loaded_name):
            loaded_name = os.path.abspath(loaded_name)
        assert os.path.samefile(loaded_name, SO_PATH), "release_lib did not load librust_ffi.so"

        fn = lib.generate_release_tag
        assert isinstance(fn, ctypes._CFuncPtr), "generate_release_tag is not a function loaded from the shared library"
        assert fn.argtypes == [ctypes.c_char_p], "generate_release_tag.argtypes must be [ctypes.c_char_p]"
        assert fn.restype is ctypes.c_char_p, "generate_release_tag.restype must be ctypes.c_char_p"

        version = _random_version()
        assert fn(version.encode()) == ("RELEASE-" + version).encode()
    finally:
        if generator is not None:
            try:
                next(generator)
                assert False, "release_lib fixture yielded more than once"
            except StopIteration:
                pass


def test_pytest_runs_successfully():
    result = subprocess.run(["pytest", PY_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"pytest failed when run against {PY_PATH}:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
