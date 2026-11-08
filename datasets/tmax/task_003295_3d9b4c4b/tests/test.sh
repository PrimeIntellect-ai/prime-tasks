#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import subprocess

import pytest

WORKDIR = "/home/user/polyglot-data"
APP = os.path.join(WORKDIR, "app")
LIB = os.path.join(WORKDIR, "libprocessor.so")
SCRIPT = os.path.join(WORKDIR, "test.sh")
LOG = os.path.join(WORKDIR, "output.log")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def install_app_wrapper(trace_path, real_path):
    os.replace(APP, real_path)
    wrapper = f'''#!/bin/sh
printf '%s\\0' "$1" >> '{trace_path}'
exec '{real_path}' "$@"
'''
    with open(APP, "w") as f:
        f.write(wrapper)
    os.chmod(APP, 0o755)


def run_property_script_once(tag):
    trace_path = f"/tmp/polyglot-app-trace-{os.getpid()}-{tag}-{secrets.token_hex(8)}"
    real_path = os.path.join(WORKDIR, f".verifier-app-real-{os.getpid()}-{tag}-{secrets.token_hex(8)}")
    install_app_wrapper(trace_path, real_path)

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    try:
        result = subprocess.run(
            ["bash", SCRIPT], cwd=WORKDIR, env=env,
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f"test.sh failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(trace_path), "test.sh did not invoke app"
        raw_trace = open(trace_path, "rb").read()
        calls = raw_trace.split(b"\0")
        if calls and calls[-1] == b"":
            calls.pop()
        args = [item.decode("utf-8") for item in calls]
        assert len(args) == 10, f"test.sh invoked app {len(args)} times instead of exactly 10"

        expected_lines = []
        input_pattern = re.compile(r"^id:(\d+),value:(\d+)$")
        for i, arg in enumerate(args):
            match = input_pattern.fullmatch(arg)
            assert match, f"Invocation {i + 1} used an invalid first argument: {arg!r}"
            ident, value = map(int, match.groups())
            assert ident <= 2147483647, "Generated id is outside the C int range"
            assert value <= 1073741823, "Generated value cannot be safely doubled as a C int"
            expected_lines.append(f"id:{ident},value:{value * 2}")

        assert os.path.isfile(LOG), "test.sh did not create output.log"
        actual_bytes = open(LOG, "rb").read()
        expected_bytes = ("\n".join(expected_lines) + "\n").encode()
        assert actual_bytes == expected_bytes, (
            "output.log must contain exactly the raw stdout produced for the 10 app "
            "invocations, one result per line"
        )
        return args
    finally:
        if os.path.exists(APP):
            os.unlink(APP)
        if os.path.exists(real_path):
            os.replace(real_path, APP)
        if os.path.exists(trace_path):
            os.unlink(trace_path)


@pytest.fixture(scope="module", autouse=True)
def prepare_and_exercise_submission():
    for path in (APP, LIB, os.path.join(WORKDIR, "processor.o"), os.path.join(WORKDIR, "main.o")):
        if os.path.exists(path):
            os.unlink(path)

    result = run(["make", "-C", WORKDIR])
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"
    assert os.path.isfile(APP), "make did not build app"
    assert os.path.isfile(LIB), "make did not build libprocessor.so"
    assert os.path.isfile(SCRIPT), "test.sh does not exist"

    first_args = run_property_script_once("first")
    second_args = run_property_script_once("second")
    assert first_args != second_args, (
        "Two independent executions of test.sh generated the same complete input sequence; "
        "the cases appear fixed rather than random"
    )


def test_makefile_builds_successfully():
    """Verify that running make succeeds without errors."""
    result = run(["make", "-C", WORKDIR])
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"


def test_libprocessor_so_exists():
    """Verify that the shared library was built."""
    assert os.path.isfile(LIB), f"Shared library {LIB} was not built."

    header = run(["readelf", "-h", LIB])
    assert header.returncode == 0, f"{LIB} is not a valid ELF shared object"
    assert re.search(r"Type:\s+DYN", header.stdout), f"{LIB} is not an ELF shared object"

    dry_run = run(["make", "-B", "-n", "-C", WORKDIR, "libprocessor.so"])
    assert dry_run.returncode == 0, "Could not inspect the libprocessor.so build recipe"
    assert re.search(r"(?:^|\s)-fpic(?:\s|$)", dry_run.stdout, re.IGNORECASE | re.MULTILINE), (
        "The library compilation command does not compile position-independent code with -fPIC"
    )


def test_library_behavior_directly():
    """Exercise the exported FFI function independently of the CLI."""
    library = ctypes.CDLL(LIB)
    process_data = library.process_data
    process_data.argtypes = [ctypes.c_char_p]
    process_data.restype = ctypes.c_void_p
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]

    cases = [(0, 0), (7, 13), (982451653, 123456)]
    for ident, value in cases:
        ptr = process_data(f"id:{ident},value:{value}".encode())
        assert ptr, "process_data unexpectedly returned NULL"
        try:
            result = ctypes.string_at(ptr).decode()
        finally:
            libc.free(ptr)
        assert result == f"id:{ident},value:{value * 2}"


def test_app_exists_and_links_dynamically():
    """Verify that the executable was built and dynamically links to libprocessor.so."""
    assert os.path.isfile(APP), f"Executable {APP} was not built."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = WORKDIR
    result = subprocess.run(["ldd", APP], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"ldd failed on {APP}"
    assert "libprocessor.so" in result.stdout, f"{APP} does not dynamically link to libprocessor.so"
    assert "libprocessor.so => not found" not in result.stdout
    assert re.search(r"libprocessor\.so\s+=>\s+" + re.escape(LIB), result.stdout), (
        "app does not resolve its dynamic dependency to the built libprocessor.so"
    )

    dynamic = run(["readelf", "-d", APP])
    assert dynamic.returncode == 0
    assert re.search(r"NEEDED.*\[libprocessor\.so\]", dynamic.stdout), (
        "app has no dynamic NEEDED entry for libprocessor.so"
    )

    for ident, value in [(1, 50), (41, 73), (secrets.randbelow(100000), secrets.randbelow(100000))]:
        executed = subprocess.run(
            [APP, f"id:{ident},value:{value}"], cwd=WORKDIR, env=env,
            capture_output=True, text=True, timeout=5
        )
        assert executed.returncode == 0
        assert executed.stdout == f"id:{ident},value:{value * 2}\n"


def test_test_script_exists():
    """Verify that the test.sh script exists."""
    assert os.path.isfile(SCRIPT), f"Test script {SCRIPT} does not exist."


def test_output_log_format():
    """Verify that output.log exists, has exactly 10 lines, and matches the correct format."""
    assert os.path.isfile(LOG), f"Output log {LOG} does not exist."

    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 10, f"Expected exactly 10 lines in {LOG}, found {len(lines)}."

    pattern = re.compile(r"^id:\d+,value:\d+$")
    for i, line in enumerate(lines):
        assert pattern.match(line), f"Line {i+1} in {LOG} does not match the expected format: '{line}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
