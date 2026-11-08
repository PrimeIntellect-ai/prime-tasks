#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tempfile

import pytest

RUST_DIR = "/home/user/test_env/rust_src"
GO_DIR = "/home/user/test_env/go_app"
LIB_PATH = "/home/user/test_env/rust_src/target/debug/libversion_check.so"
LOG_PATH = "/home/user/test_output.log"


def assert_elf_shared_library(path):
    with open(path, "rb") as f:
        header = f.read(64)
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF binary"
    assert len(header) >= 18, f"{path} has a truncated ELF header"
    byteorder = "little" if header[5] == 1 else "big" if header[5] == 2 else None
    assert byteorder is not None, f"{path} has an invalid ELF byte order"
    elf_type = int.from_bytes(header[16:18], byteorder)
    assert elf_type == 3, f"{path} is not an ELF shared object"


def assert_version_function(path):
    probe = r'''
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.get_version
fn.argtypes = []
fn.restype = ctypes.c_void_p
for _ in range(32):
    ptr = fn()
    if not ptr:
        raise SystemExit("get_version returned NULL")
    value = ctypes.string_at(ptr, 6)
    if value != b"1.5.2\0":
        raise SystemExit("get_version returned invalid data: %r" % (value,))
'''
    result = subprocess.run(
        ["python3", "-c", probe, path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Could not load and call get_version from {path}:\n{result.stdout}"
    )


def test_rust_library_built():
    """Verify that the Rust project was successfully built as a shared library."""
    assert os.path.isfile(LIB_PATH), f"Expected compiled Rust shared library at {LIB_PATH}, but it is missing. Did you run 'cargo build'?"


def test_go_test_output_exists():
    """Verify that the test output log was created."""
    assert os.path.isfile(LOG_PATH), f"Expected Go test output log at {LOG_PATH}, but it is missing."


def test_go_test_passed():
    """Verify that the Go test suite was run successfully and passed."""
    assert os.path.isfile(LOG_PATH), f"Cannot check test results because {LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        content = f.read()

    assert "PASS" in content, "The test output log does not contain 'PASS'. Ensure the tests ran successfully."
    assert "TestVersionParser" in content, "The test output log does not indicate that 'TestVersionParser' was run."
    assert "PASS: TestVersionParser" in content, "The test output log does not contain the expected successful test pass message ('PASS: TestVersionParser')."


def test_library_is_loadable_and_returns_expected_version():
    """Reject placeholder files and exercise the submitted shared library directly."""
    assert_elf_shared_library(LIB_PATH)
    assert_version_function(LIB_PATH)


def test_rust_source_rebuilds_to_working_library():
    """Build the submitted Rust source independently and exercise that result."""
    with tempfile.TemporaryDirectory(prefix="version-check-target-") as target_dir:
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = target_dir
        result = subprocess.run(
            ["cargo", "build"],
            cwd=RUST_DIR,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        assert result.returncode == 0, f"The submitted Rust source does not build:\n{result.stdout}"
        rebuilt = os.path.join(target_dir, "debug", "libversion_check.so")
        assert os.path.isfile(rebuilt), f"cargo build did not produce {rebuilt}"
        assert_elf_shared_library(rebuilt)
        assert_version_function(rebuilt)


def test_go_suite_really_passes_with_required_environment():
    """Run the real Go suite without trusting the contents of the saved log."""
    env = os.environ.copy()
    env["STRICT_SEMVER"] = "1"
    old_ld_path = env.get("LD_LIBRARY_PATH", "")
    lib_dir = os.path.dirname(LIB_PATH)
    env["LD_LIBRARY_PATH"] = lib_dir + ((":" + old_ld_path) if old_ld_path else "")

    result = subprocess.run(
        ["go", "test", "-v", "-count=1"],
        cwd=GO_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"The Go test suite failed when actually executed:\n{result.stdout}"
    assert "=== RUN   TestVersionParser" in result.stdout, (
        f"The actual verbose Go test run did not execute TestVersionParser:\n{result.stdout}"
    )
    assert "--- PASS: TestVersionParser" in result.stdout, (
        f"TestVersionParser did not pass in the actual Go test run:\n{result.stdout}"
    )
    assert "PASS" in result.stdout, f"The actual Go test run did not report success:\n{result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
