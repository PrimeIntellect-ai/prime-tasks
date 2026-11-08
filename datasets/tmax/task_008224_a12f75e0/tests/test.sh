#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/release_manager"
FIXTURES_DIR = os.path.join(PROJECT_DIR, "fixtures")
CI_SCRIPT = os.path.join(PROJECT_DIR, "ci.sh")
CI_RESULTS = os.path.join(PROJECT_DIR, "ci_results.log")
RELEASE_BINARY = os.path.join(PROJECT_DIR, "target", "release", "release_checker")

EXPECTED_FIXTURES = {
    "valid.json": {
        "version": "2.1.0",
        "data": "update_package_A",
        "checksum": "4027419ef9c2b48cd029fc12d592fba499ffdc7bde0991c28cde3c467a90f1d1"
    },
    "bad_checksum.json": {
        "version": "2.1.0",
        "data": "update_package_A",
        "checksum": "badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"
    },
    "downgrade.json": {
        "version": "1.5.0",
        "data": "update_package_B",
        "checksum": "b80b2a32c25bc5e5108cc9c66af7e20ecba094de193c78d5312010fb09e7de7b"
    }
}

EXPECTED_LINES = ["PASS", "FAIL: CHECKSUM", "FAIL: DOWNGRADE"]


def read_result_lines():
    assert os.path.isfile(CI_RESULTS), f"CI results log not found at {CI_RESULTS}"
    with open(CI_RESULTS, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def run_ci():
    return subprocess.run(
        [CI_SCRIPT],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )


@pytest.fixture(scope="session", autouse=True)
def compile_project():
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        "cargo build --release failed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_rust_binary_compiled():
    """Verify that the Rust project compiles to an executable release binary."""
    assert os.path.isfile(RELEASE_BINARY), (
        f"The release binary was not found at {RELEASE_BINARY}. "
        "Did you run 'cargo build --release' successfully?"
    )
    assert os.access(RELEASE_BINARY, os.X_OK), (
        f"The file at {RELEASE_BINARY} is not executable."
    )
    with open(RELEASE_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not an ELF binary."


def test_fixtures_exist_and_valid():
    """Verify that the test fixtures are created correctly with the specified content."""
    assert os.path.isdir(FIXTURES_DIR), f"Fixtures directory not found at {FIXTURES_DIR}"

    for filename, expected_data in EXPECTED_FIXTURES.items():
        filepath = os.path.join(FIXTURES_DIR, filename)
        assert os.path.isfile(filepath), f"Fixture file missing: {filepath}"

        with open(filepath, "r") as f:
            try:
                actual_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Fixture file {filepath} is not valid JSON.")

        assert actual_data == expected_data, (
            f"Content of {filepath} does not match expected values.\n"
            f"Expected: {expected_data}\nActual: {actual_data}"
        )


def test_ci_script_executable():
    """Verify that the CI script exists and is executable."""
    assert os.path.isfile(CI_SCRIPT), f"CI script not found at {CI_SCRIPT}"
    assert os.access(CI_SCRIPT, os.X_OK), f"CI script at {CI_SCRIPT} is not executable."


def test_release_binary_behavior():
    """Execute the built artifact on verifier-generated manifests."""
    nonce = secrets.token_hex(24)

    cases = [
        ("9.0.0", nonce + "-major", "8.99.99", True, "PASS"),
        ("8.100.0", nonce + "-minor", "8.99.99", True, "PASS"),
        ("8.99.100", nonce + "-patch", "8.99.99", True, "PASS"),
        ("8.99.99", nonce + "-equal", "8.99.99", True, "FAIL: DOWNGRADE"),
        ("7.999.999", nonce + "-lower-major", "8.0.0", True, "FAIL: DOWNGRADE"),
        ("8.98.999", nonce + "-lower-minor", "8.99.0", True, "FAIL: DOWNGRADE"),
        ("8.99.98", nonce + "-lower-patch", "8.99.99", True, "FAIL: DOWNGRADE"),
        ("99.0.0", nonce + "-bad-sum", "1.0.0", False, "FAIL: CHECKSUM"),
    ]

    with tempfile.TemporaryDirectory() as tempdir:
        for index, (version, data, previous, good_checksum, expected) in enumerate(cases):
            checksum = hashlib.sha256(data.encode()).hexdigest()
            if not good_checksum:
                checksum = ("0" if checksum[0] != "0" else "1") + checksum[1:]

            path = os.path.join(tempdir, f"case_{index}.json")
            with open(path, "w") as f:
                json.dump({"version": version, "data": data, "checksum": checksum}, f)

            result = subprocess.run(
                [RELEASE_BINARY, path, previous],
                cwd=PROJECT_DIR,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"release_checker exited with {result.returncode} for case {index}.\n"
                f"stderr: {result.stderr}"
            )
            assert result.stdout.rstrip("\n") == expected, (
                f"Unexpected output for case {index}: expected {expected!r}, "
                f"got {result.stdout!r}"
            )


def test_ci_pipeline_execution():
    """Run ci.sh and ensure its log is produced by the named fixtures in order."""
    assert os.path.isfile(CI_SCRIPT), f"CI script not found at {CI_SCRIPT}"
    assert os.access(CI_SCRIPT, os.X_OK), f"CI script at {CI_SCRIPT} is not executable."

    originals = {}
    for filename in EXPECTED_FIXTURES:
        path = os.path.join(FIXTURES_DIR, filename)
        with open(path, "rb") as f:
            originals[filename] = f.read()

    nonce = secrets.token_hex(20)
    altered = {
        "valid.json": {
            "version": "9.0.0",
            "data": nonce + "-first",
            "checksum": "0" * 64,
        },
        "bad_checksum.json": {
            "version": "2.0.0",
            "data": nonce + "-second",
        },
        "downgrade.json": {
            "version": "2.0.1",
            "data": nonce + "-third",
        },
    }
    for value in altered.values():
        if "checksum" not in value:
            value["checksum"] = hashlib.sha256(value["data"].encode()).hexdigest()

    try:
        for filename, value in altered.items():
            with open(os.path.join(FIXTURES_DIR, filename), "w") as f:
                json.dump(value, f)

        if os.path.exists(CI_RESULTS):
            os.remove(CI_RESULTS)
        result = run_ci()
        assert result.returncode == 0, (
            f"ci.sh failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert read_result_lines() == ["FAIL: CHECKSUM", "FAIL: DOWNGRADE", "PASS"], (
            "ci.sh did not run the compiled checker against valid.json, "
            "bad_checksum.json, and downgrade.json in the required order "
            "using previous version 2.0.0."
        )
    finally:
        for filename, content in originals.items():
            with open(os.path.join(FIXTURES_DIR, filename), "wb") as f:
                f.write(content)

    result = run_ci()
    assert result.returncode == 0, (
        f"ci.sh failed on the required fixtures.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_ci_results_log():
    """Verify that the CI results log matches the expected output exactly."""
    lines = read_result_lines()
    assert lines == EXPECTED_LINES, (
        f"The contents of {CI_RESULTS} do not match the expected output.\n"
        f"Expected: {EXPECTED_LINES}\nActual: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
