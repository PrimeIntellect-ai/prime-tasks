#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import struct
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/deploy_api"
BINARY = "/home/user/deploy_api/target/x86_64-unknown-linux-musl/release/deploy_api"
JSON_PATH = "/home/user/deployment_deps.json"
MAIN_RS = "/home/user/deploy_api/src/main.rs"
FIXED_PAYLOAD = {
    "list1": ["1.2.3", "3.0.1", "2.1.0"],
    "list2": ["2.1.0", "4.0.0", "1.0.0"],
}
FIXED_EXPECTED = {
    "merged": ["4.0.0", "3.0.1", "2.1.0", "1.2.3", "1.0.0"]
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_x86_64_static_elf(path):
    with open(path, "rb") as f:
        header = f.read(64)

    assert header[:4] == b"\x7fELF", "The submitted executable is not an ELF binary."
    assert header[4] == 2, "The submitted ELF is not 64-bit."
    assert header[5] == 1, "The submitted ELF is not little-endian."
    assert struct.unpack_from("<H", header, 18)[0] == 62, "The submitted ELF is not x86_64."

    result = subprocess.run(
        ["readelf", "-l", path], text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, result.stderr
    assert "INTERP" not in result.stdout, (
        "The deployment binary has a dynamic program interpreter; the musl target "
        "binary is expected to be statically linked."
    )


def post_json(payload):
    request = urllib.request.Request(
        "http://127.0.0.1:8080/merge",
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=3) as response:
        assert response.status == 200
        return response.read()


def expected_for(payload):
    return {"merged": sorted(set(payload["list1"] + payload["list2"]), reverse=True)}


def test_binary_exists_executable_architecture_and_matches_source_build():
    assert os.path.exists(BINARY), f"The musl release binary was not found at {BINARY}."
    assert os.path.isfile(BINARY), f"The path {BINARY} is not a file."
    assert os.access(BINARY, os.X_OK), f"The binary at {BINARY} is not executable."
    assert_x86_64_static_elf(BINARY)

    submitted_hash = sha256(BINARY)
    result = subprocess.run(
        [
            "cargo", "build", "--offline", "--release",
            "--target", "x86_64-unknown-linux-musl",
        ],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=300,
        env={**os.environ, "CARGO_HOME": "/usr/local/cargo", "RUSTUP_HOME": "/usr/local/rustup"},
    )
    assert result.returncode == 0, (
        "The Rust source does not compile for x86_64-unknown-linux-musl in release mode.\n"
        + result.stdout + "\n" + result.stderr
    )
    assert os.path.exists(BINARY) and os.path.isfile(BINARY)
    assert os.access(BINARY, os.X_OK)
    assert sha256(BINARY) == submitted_hash, (
        "The submitted binary was not the release musl artifact produced by the current source."
    )
    assert_x86_64_static_elf(BINARY)


def test_json_output_exists_and_correct():
    assert os.path.exists(JSON_PATH), f"The output JSON file was not found at {JSON_PATH}."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert data == FIXED_EXPECTED, f"The JSON output does not match the expected result. Got: {data}"


def test_main_rs_fixed_and_still_uses_axum():
    assert os.path.exists(MAIN_RS), f"The source file {MAIN_RS} is missing."
    with open(MAIN_RS, "r") as f:
        content = f.read()
    assert "axum" in content, "The axum framework usage seems to have been removed from src/main.rs."


@pytest.fixture(scope="module")
def running_service():
    # The instruction leaves the service running; stop that instance so the verifier
    # can prove that the submitted artifact itself starts and owns port 8080.
    subprocess.run(["pkill", "-x", "deploy_api"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    proc = subprocess.Popen(
        [BINARY], cwd=PROJECT, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode("utf-8", errors="replace")
                pytest.fail(f"The submitted binary exited before serving requests: {stderr}")
            try:
                body = post_json({"list1": [], "list2": []})
                assert json.loads(body) == {"merged": []}
                break
            except (OSError, urllib.error.URLError) as exc:
                last_error = exc
                time.sleep(0.1)
        else:
            pytest.fail(f"The submitted binary did not start on 127.0.0.1:8080: {last_error}")
        yield proc
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def test_saved_file_is_exact_raw_response_from_submitted_service(running_service):
    body = post_json(FIXED_PAYLOAD)
    assert json.loads(body) == FIXED_EXPECTED
    with open(JSON_PATH, "rb") as f:
        saved = f.read()
    assert saved == body, (
        "deployment_deps.json is not the exact raw response returned by the submitted service "
        "for the required payload."
    )
    assert running_service.poll() is None


def test_merge_endpoint_on_derived_inputs(running_service):
    token = secrets.token_hex(8)
    cases = [
        {
            "list1": [f"9.{token}.1", "2.0.0", f"5.{token}.0", "2.0.0"],
            "list2": [f"5.{token}.0", "10.0.0", f"1.{token}.9", "10.0.0"],
        },
        {
            "list1": [f"z-{token}", f"a-{token}", f"m-{token}"],
            "list2": [f"a-{token}", f"y-{token}", f"m-{token}"],
        },
        {
            "list1": [],
            "list2": [f"3-{token}", f"3-{token}", f"4-{token}"],
        },
    ]

    for payload in cases:
        body = post_json(payload)
        try:
            actual = json.loads(body)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The endpoint returned invalid JSON: {exc}: {body!r}")
        assert actual == expected_for(payload), (
            f"Incorrect union/deduplication/descending sort for {payload}: {actual}"
        )
        assert running_service.poll() is None
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
