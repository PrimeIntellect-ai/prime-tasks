#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import subprocess
import tempfile

PROJECT = "/home/user/project"
MOCK = os.path.join(PROJECT, "libmock.so")
APP = os.path.join(PROJECT, "app")
RESULT = os.path.join(PROJECT, "leak_size.txt")


def run(cmd, *, env=None, timeout=30):
    return subprocess.run(
        cmd,
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_libmock_so_exists():
    path = "/home/user/project/libmock.so"
    assert os.path.isfile(path), f"Mock shared library {path} is missing."


def test_leak_size_file_exists():
    path = "/home/user/project/leak_size.txt"
    assert os.path.isfile(path), f"Result file {path} is missing."


def test_leak_size_correct():
    path = "/home/user/project/leak_size.txt"
    assert os.path.isfile(path), f"Result file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "256", f"Expected leak size to be '256', but got '{content}'."


def test_mock_is_loadable_shared_library_with_only_required_override():
    header = run(["readelf", "-h", MOCK])
    assert header.returncode == 0, f"libmock.so is not a valid ELF file: {header.stderr}"
    assert re.search(r"Type:\s+DYN\s+\(Shared object file\)", header.stdout), \
        "libmock.so is not an ELF shared object"

    symbols = run(["nm", "-D", "--defined-only", MOCK])
    assert symbols.returncode == 0, f"Could not inspect libmock.so: {symbols.stderr}"
    defined = {
        line.split()[-1].split("@", 1)[0]
        for line in symbols.stdout.splitlines()
        if line.split()
    }
    assert "sm_get_version" in defined, "libmock.so does not define sm_get_version"
    assert "sm_process" not in defined, "libmock.so must not override sm_process"

    lib = ctypes.CDLL(MOCK)
    get_version = lib.sm_get_version
    get_version.restype = ctypes.c_char_p
    assert get_version() == b"2.1.0", "sm_get_version() must return 2.1.0"


def test_preload_activates_v2_and_uses_original_processing_symbol():
    baseline = run([APP])
    assert baseline.returncode == 0, baseline.stderr
    assert "Library version detected: 1.5.0" in baseline.stdout
    assert "Using V1 slow path..." in baseline.stdout

    env = os.environ.copy()
    env["LD_PRELOAD"] = MOCK
    env["LD_DEBUG"] = "bindings"
    injected = run([APP], env=env)
    assert injected.returncode == 0, injected.stderr
    assert "Library version detected: 2.1.0" in injected.stdout
    assert "Using V2 fast path..." in injected.stdout
    assert "State machine processed: v2_fast_path_data" in injected.stdout

    version_lines = [
        line for line in injected.stderr.splitlines()
        if "sm_get_version" in line and "binding file" in line
    ]
    process_lines = [
        line for line in injected.stderr.splitlines()
        if "sm_process" in line and "binding file" in line
    ]
    assert any("libmock.so" in line for line in version_lines), \
        "sm_get_version was not resolved from libmock.so"
    assert any("libstatemachine.so" in line for line in process_lines), \
        "sm_process was not resolved from the original libstatemachine.so"


def test_valgrind_measurement_matches_reported_result():
    fd, log_path = tempfile.mkstemp(prefix="valgrind-", suffix=".log")
    os.close(fd)
    try:
        env = os.environ.copy()
        env["LD_PRELOAD"] = MOCK
        env["LC_ALL"] = "C"
        measured = run([
            "valgrind",
            "--leak-check=full",
            "--show-leak-kinds=all",
            "--log-file=" + log_path,
            APP,
        ], env=env, timeout=60)
        assert measured.returncode == 0, measured.stderr
        assert "Library version detected: 2.1.0" in measured.stdout
        assert "Using V2 fast path..." in measured.stdout
        assert "State machine processed: v2_fast_path_data" in measured.stdout

        with open(log_path, "r") as f:
            valgrind_log = f.read()
        matches = re.findall(r"definitely lost:\s*([0-9,]+) bytes in [0-9,]+ blocks", valgrind_log)
        assert matches, f"Valgrind did not report a definitely-lost total:\n{valgrind_log}"
        definitely_lost = int(matches[-1].replace(",", ""))

        with open(RESULT, "r") as f:
            reported = f.read().strip()
        assert reported.isdigit(), "leak_size.txt must contain an integer"
        assert int(reported) == definitely_lost, \
            f"leak_size.txt reports {reported}, but Valgrind measured {definitely_lost}"
    finally:
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
