#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import stat
import struct
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/build_and_test.sh"
LIB_PATH = "/home/user/lib/libdataproc.so"
BIN_PATH = "/home/user/bin/test_runner"
DATA_SOURCE = "/home/user/src/data_processor.c"
RUNNER_SOURCE = "/home/user/src/test_runner.c"

NONCE = secrets.token_hex(8)
NONCE_FUNCTION = f"verifier_nonce_{NONCE}"
NONCE_VALUE = secrets.randbelow(1000000) + 1
NOARG_EXIT = secrets.randbelow(100) + 2

@pytest.fixture(scope="session", autouse=True)
def run_script():
    """Ensure the script exists and is executable, then build fresh artifacts."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Script {SCRIPT_PATH} is not executable."

    with open(DATA_SOURCE, "r") as f:
        original_data_source = f.read()
    with open(RUNNER_SOURCE, "r") as f:
        original_runner_source = f.read()

    assert "if (argc < 2) return 1;" in original_runner_source

    challenged_data_source = original_data_source + f"\nint {NONCE_FUNCTION}(void) {{ return {NONCE_VALUE}; }}\n"
    challenged_runner_source = original_runner_source.replace(
        "if (argc < 2) return 1;",
        f"if (argc < 2) return {NOARG_EXIT};",
        1,
    )

    for path in (LIB_PATH, BIN_PATH, "/home/user/test_results.json", "/home/user/status.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        with open(DATA_SOURCE, "w") as f:
            f.write(challenged_data_source)
        with open(RUNNER_SOURCE, "w") as f:
            f.write(challenged_runner_source)

        result = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True)
    finally:
        with open(DATA_SOURCE, "w") as f:
            f.write(original_data_source)
        with open(RUNNER_SOURCE, "w") as f:
            f.write(original_runner_source)

    assert result.returncode == 0, (
        "Script executed with non-zero exit code.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_shared_library_created():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not created."

    result = subprocess.run(["file", LIB_PATH], capture_output=True, text=True)
    assert "shared object" in result.stdout.lower(), f"{LIB_PATH} is not compiled as a shared object."


def test_shared_library_was_built_from_supplied_source():
    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, NONCE_FUNCTION), "Shared library was not built from the supplied data_processor.c."
    function = getattr(lib, NONCE_FUNCTION)
    function.restype = ctypes.c_int
    assert function() == NONCE_VALUE

    symbols = subprocess.run(["nm", "-D", LIB_PATH], capture_output=True, text=True, check=True)
    assert " process_data" in symbols.stdout, "Shared library does not export process_data."


def test_test_runner_created():
    assert os.path.isfile(BIN_PATH), f"Executable {BIN_PATH} was not created."

    st = os.stat(BIN_PATH)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"{BIN_PATH} is not executable."


def test_test_runner_was_built_from_supplied_source_and_linked():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/lib"

    noarg = subprocess.run([BIN_PATH], capture_output=True, env=env)
    assert noarg.returncode == NOARG_EXIT, "test_runner was not built from the supplied test_runner.c."

    dynamic = subprocess.run(["readelf", "-d", BIN_PATH], capture_output=True, text=True, check=True)
    assert "Shared library: [libdataproc.so]" in dynamic.stdout, "test_runner is not linked against libdataproc.so."

    symbols = subprocess.run(["nm", "-D", BIN_PATH], capture_output=True, text=True, check=True)
    assert any(" U process_data" in line for line in symbols.stdout.splitlines()), "test_runner does not dynamically use process_data."

    linked = subprocess.run(["ldd", BIN_PATH], capture_output=True, text=True, env=env, check=True)
    assert "/home/user/lib/libdataproc.so" in linked.stdout, "test_runner does not resolve libdataproc.so from /home/user/lib."


def test_runner_on_derived_inputs():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/lib"

    for _ in range(3):
        value = secrets.randbelow(2000000001) - 1000000000
        with tempfile.NamedTemporaryFile() as data_file:
            data_file.write(struct.pack("<i", value))
            data_file.flush()
            result = subprocess.run([BIN_PATH, data_file.name], capture_output=True, text=True, env=env)

        assert result.returncode == 0, f"test_runner failed for value {value}: {result.stderr}"
        assert result.stdout == f'{{"value": {value}}}\n', (
            f"test_runner produced an incorrect result for derived input {value}: {result.stdout!r}"
        )


def test_test_results_json():
    res_path = "/home/user/test_results.json"
    assert os.path.isfile(res_path), f"Results file {res_path} was not created."

    with open(res_path, "r") as f:
        content = f.read()

    assert content.strip() == '{"value": 42}', f"Unexpected content in {res_path}: {content!r}"


def test_status_log():
    log_path = "/home/user/status.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."

    with open(log_path, "r") as f:
        content = f.read()

    assert content.strip() == "PASS", f"Unexpected content in {log_path}: {content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
