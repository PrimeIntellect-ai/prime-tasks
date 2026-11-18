#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import pytest

PROJECT_DIR = "/home/user/project_sync"
DATA_DIR = os.path.join(PROJECT_DIR, "data")
EXE_PATH = os.path.join(PROJECT_DIR, "fast_checksum")
JSON_PATH = os.path.join(PROJECT_DIR, "api_payload.json")


def fletcher16(data: bytes) -> int:
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1


def expected_results():
    results = {}
    for fname in sorted(os.listdir(DATA_DIR)):
        file_path = os.path.join(DATA_DIR, fname)
        if os.path.isfile(file_path):
            with open(file_path, "rb") as fp:
                results[fname] = fletcher16(fp.read())
    return results


def load_payload():
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} not found. Did you run the executable?"
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")


def assert_payload_matches(payload):
    assert "files" in payload, "'files' key missing in JSON payload."
    expected = expected_results()
    assert payload["files"] == expected, (
        "JSON payload does not match expected checksums.\n"
        f"Expected: {expected}\n"
        f"Got: {payload['files']}"
    )
    assert list(payload["files"].keys()) == sorted(expected), (
        "Files in the JSON payload are not in alphabetical order."
    )


def run_under_valgrind():
    cmd = [
        "valgrind",
        "--error-exitcode=1",
        "--leak-check=full",
        EXE_PATH,
    ]
    return subprocess.run(cmd, capture_output=True, text=True, cwd=PROJECT_DIR)


def install_runtime_corpus():
    os.makedirs(DATA_DIR, exist_ok=True)
    for entry in os.scandir(DATA_DIR):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)

    corpus = {
        "00_empty.bin": b"",
        "alpha_" + secrets.token_hex(6) + ".bin": secrets.token_bytes(1),
        "middle_" + secrets.token_hex(6) + ".dat": secrets.token_bytes(257),
        "omega_" + secrets.token_hex(6) + ".bin": secrets.token_bytes(8193),
        "text_" + secrets.token_hex(6) + ".txt": b"runtime-" + secrets.token_bytes(37),
    }
    for name, contents in corpus.items():
        with open(os.path.join(DATA_DIR, name), "wb") as fp:
            fp.write(contents)


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} not found. Did you compile the C++ code?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as fp:
        assert fp.read(4) == b"\x7fELF", "fast_checksum must be a compiled executable."


def test_api_payload_json():
    # Preserve the original final-state check before changing any fixtures.
    payload = load_payload()
    assert_payload_matches(payload)

    # Replace the fixed fixtures with unpredictable inputs, remove the old output,
    # and require the submitted executable itself to regenerate the payload.
    install_runtime_corpus()
    if os.path.lexists(JSON_PATH):
        os.unlink(JSON_PATH)

    result = run_under_valgrind()
    assert result.returncode == 0, (
        f"Valgrind reported memory errors or leaks. Return code: {result.returncode}\n"
        f"Valgrind Output:\n{result.stderr}"
    )

    regenerated = load_payload()
    assert_payload_matches(regenerated)


def test_valgrind_memory_safety():
    if not os.path.isfile(EXE_PATH):
        pytest.fail("Executable missing, cannot run valgrind.")

    result = run_under_valgrind()
    assert result.returncode == 0, (
        f"Valgrind reported memory errors or leaks. Return code: {result.returncode}\n"
        f"Valgrind Output:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
