#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import subprocess
import tempfile

import pytest

C_DIR = "/home/user/pipeline/c_src"
RUST_DIR = "/home/user/pipeline/rust_src"
LIB_PATH = os.path.join(C_DIR, "libfilter.so")
BINARY_PATH = os.path.join(RUST_DIR, "target/debug/parser")


@pytest.fixture(scope="module", autouse=True)
def rebuild_projects():
    """Verify that the repaired Makefile and Rust project actually build."""
    c_build = subprocess.run(
        ["make", "-B", "libfilter.so"],
        cwd=C_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert c_build.returncode == 0, (
        "C shared library failed to rebuild from the Makefile:\n"
        + c_build.stdout
        + c_build.stderr
    )

    rust_build = subprocess.run(
        ["cargo", "build", "--offline"],
        cwd=RUST_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert rust_build.returncode == 0, (
        "Rust parser failed to build:\n" + rust_build.stdout + rust_build.stderr
    )


def test_output_json_exists():
    """Check if the output.json file was created."""
    output_path = "/home/user/output.json"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"


def test_output_json_content():
    """Check if the output.json contains the correct parsed events."""
    output_path = "/home/user/output.json"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("output.json is not valid JSON")

    assert isinstance(data, list), "output.json should contain a JSON array"

    expected = [
        {"code": 200, "data": "login_success"},
        {"code": 150, "data": "processing"}
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} events, but got {len(data)}"

    for i, expected_event in enumerate(expected):
        assert data[i] == expected_event, f"Event at index {i} mismatch: expected {expected_event}, got {data[i]}"


def test_libfilter_so_is_shared_object():
    """Check if libfilter.so was built as a shared object."""
    assert os.path.isfile(LIB_PATH), f"Shared library missing: {LIB_PATH}"

    result = subprocess.run(["file", LIB_PATH], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run 'file' command"

    output = result.stdout.lower()
    assert "shared object" in output, f"libfilter.so is not a shared object. 'file' output: {output}"


def test_libfilter_function_behavior():
    """Exercise the exported C function, including its boundary values."""
    library = ctypes.CDLL(LIB_PATH)
    is_valid_event = library.is_valid_event
    is_valid_event.argtypes = [ctypes.c_int]
    is_valid_event.restype = ctypes.c_int

    for code in [-1000, 0, 99, 100, 101, 299, 300, 301, 1000]:
        expected = 1 if 100 <= code <= 300 else 0
        assert is_valid_event(code) == expected, (
            f"is_valid_event({code}) returned the wrong result"
        )


def test_rust_binary_compiled():
    """Check if the Rust binary was compiled successfully."""
    assert os.path.isfile(BINARY_PATH), "Rust binary was not compiled successfully (expected at target/debug/parser)"

    result = subprocess.run(["file", BINARY_PATH], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to inspect the Rust binary"
    description = result.stdout.lower()
    assert "elf" in description and "executable" in description, (
        f"Expected a compiled ELF executable, got: {result.stdout}"
    )
    assert os.access(BINARY_PATH, os.X_OK), "Rust parser binary is not executable"

    dynamic = subprocess.run(
        ["readelf", "-d", BINARY_PATH], capture_output=True, text=True
    )
    assert dynamic.returncode == 0, "Failed to inspect parser dynamic dependencies"
    assert "libfilter.so" in dynamic.stdout, (
        "Rust parser is not dynamically linked against libfilter.so"
    )


def test_parser_on_generated_input():
    """Run the compiled parser on fresh inputs and derive the expected JSON independently."""
    rng = random.SystemRandom()
    codes = [99, 100, 150, 300, 301, -7, 450]
    codes.extend(rng.randint(-500, 700) for _ in range(9))

    lines = []
    expected = []
    for index, code in enumerate(codes):
        data = f"generated payload {index} {rng.randrange(1_000_000_000)}"
        lines.extend([f"BEGIN {code}", f"DATA {data}", "END"])
        if 100 <= code <= 300:
            expected.append({"code": code, "data": data})

    with tempfile.TemporaryDirectory() as temp_dir:
        input_path = os.path.join(temp_dir, "generated.log")
        output_path = os.path.join(temp_dir, "generated.json")
        with open(input_path, "w") as stream:
            stream.write("\n".join(lines) + "\n")

        env = os.environ.copy()
        old_path = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = C_DIR + ((":" + old_path) if old_path else "")
        result = subprocess.run(
            [BINARY_PATH, input_path, output_path],
            cwd=RUST_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "Parser failed on generated input:\n" + result.stdout + result.stderr
        )
        assert os.path.isfile(output_path), "Parser did not create its requested output file"

        try:
            with open(output_path, "r") as stream:
                actual = json.load(stream)
        except json.JSONDecodeError as error:
            pytest.fail(f"Parser produced invalid JSON: {error}")

        assert actual == expected, (
            f"Parser output mismatch for generated input: expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
