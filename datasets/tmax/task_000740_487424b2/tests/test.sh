#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/deploy_mock_lib.sh"
DEPS_PATH = "/home/user/deps.json"
VERSION_PATH = "/opt/sec_libs/version.txt"
LOG_PATH = "/home/user/pipeline.log"
BUILD_DIR = "/home/user/build"


def configure(lib_name, min_version, symbol, installed_version):
    with open(DEPS_PATH, "w") as f:
        json.dump({
            "lib_name": lib_name,
            "min_version": min_version,
            "symbol": symbol,
        }, f)
    with open(VERSION_PATH, "w") as f:
        f.write(installed_version + "\n")


def execute_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def assert_log(expected):
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH) as f:
        content = f.read().strip()
    assert content == expected, f"Expected log content {expected!r}, got {content!r}"


def assert_mock_library(lib_name, symbol):
    so_path = os.path.join(BUILD_DIR, lib_name + ".so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not created."

    with open(so_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {so_path} is not a valid ELF file."

    header = subprocess.run(
        ["readelf", "-h", so_path], capture_output=True, text=True
    )
    assert header.returncode == 0, f"readelf failed for {so_path}: {header.stderr}"
    assert "Class:" in header.stdout and "ELF64" in header.stdout, (
        f"Library {so_path} is not ELF64"
    )
    assert "Machine:" in header.stdout and "X86-64" in header.stdout, (
        f"Library {so_path} is not an x86_64 ELF"
    )

    result = subprocess.run(["nm", "-D", so_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run nm on {so_path}: {result.stderr}"
    exported = any(
        len(parts) >= 3 and parts[1] == "T" and parts[2] == symbol
        for parts in (line.split() for line in result.stdout.splitlines())
    )
    assert exported, (
        f"Symbol {symbol!r} is not exported as a global text symbol (T) in {so_path}."
    )

    library = ctypes.CDLL(so_path)
    function = getattr(library, symbol)
    function.argtypes = []
    function.restype = ctypes.c_long
    assert function() == 0, f"Exported function {symbol!r} did not return 0"


def run_case(lib_name, min_version, symbol, installed_version, expected_log,
             expect_library):
    so_path = os.path.join(BUILD_DIR, lib_name + ".so")
    if os.path.exists(so_path):
        os.remove(so_path)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    configure(lib_name, min_version, symbol, installed_version)
    execute_script()
    assert_log(expected_log)

    if expect_library:
        assert_mock_library(lib_name, symbol)
    else:
        assert not os.path.exists(so_path), (
            f"Script created {so_path} even though the installed version was up to date"
        )


def test_complete_dynamic_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    # Preserve and exercise the original setup configuration and assertions.
    run_case(
        "libwebsec", "2.4.1", "websec_verify_token", "2.1.9",
        "MOCK_BUILT", True,
    )

    # Use unpredictable names so fixed library and symbol strings cannot pass.
    token1 = secrets.token_hex(8)
    run_case(
        "libdynamic_" + token1,
        "10.3.7",
        "dynamic_check_" + token1,
        "9.99.99",
        "MOCK_BUILT",
        True,
    )

    # Equality is an up-to-date semantic-version case and must not build a mock.
    token2 = secrets.token_hex(8)
    equal_version = f"{secrets.randbelow(20) + 1}.{secrets.randbelow(20)}.{secrets.randbelow(50)}"
    run_case(
        "libequal_" + token2,
        equal_version,
        "equal_check_" + token2,
        equal_version,
        "SYSTEM_UP_TO_DATE",
        False,
    )

    # This greater-than case defeats ordinary lexicographic string comparison.
    token3 = secrets.token_hex(8)
    run_case(
        "libnewer_" + token3,
        "2.99.99",
        "newer_check_" + token3,
        "10.0.0",
        "SYSTEM_UP_TO_DATE",
        False,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
