#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import subprocess
import pytest

MANIFEST_PATH = "/home/user/deploy_manifest.json"
ROSTER_PATH = "/home/user/roster.json"
GO_SOURCE_PATH = "/home/user/process_release.go"


def expected_roster_for(manifest):
    allowed_regions = set(manifest.get("global_allowed_regions", []))
    expected_roster = []

    for service in manifest.get("services", []):
        region = service.get("target_region")
        mem_limit = service.get("memory_limit_mb", 0)
        req_mem = service.get("required_memory_mb", 0)

        if region in allowed_regions and mem_limit >= req_mem:
            name = service.get("name", "")
            version = service.get("version", "")
            raw_token = f"{name}:{version}".encode("utf-8")
            encoded_token = base64.b32encode(raw_token).decode("utf-8").rstrip("=")
            expected_roster.append({"service": name, "token": encoded_token})

    expected_roster.sort(key=lambda x: x["service"])
    return expected_roster


def run_go_program():
    if os.path.exists(ROSTER_PATH):
        os.remove(ROSTER_PATH)
    try:
        subprocess.run(
            ["go", "run", GO_SOURCE_PATH],
            cwd="/home/user",
            check=True,
            timeout=60,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"The Go program failed to run: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("The Go program did not finish within 60 seconds.")
    assert os.path.isfile(ROSTER_PATH), f"Running {GO_SOURCE_PATH} did not produce {ROSTER_PATH}."


def test_go_program_exists_and_executes():
    assert os.path.isfile(GO_SOURCE_PATH), f"The required Go source file {GO_SOURCE_PATH} does not exist."
    assert os.path.isfile(MANIFEST_PATH), f"The input file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "rb") as f:
        original_manifest = f.read()

    challenge_manifest = {
        "global_allowed_regions": ["region-b", "region-a"],
        "services": [
            {
                "name": "zeta-service",
                "version": "v7.2.1",
                "memory_limit_mb": 300,
                "required_memory_mb": 300,
                "target_region": "region-a",
            },
            {
                "name": "alpha-disallowed",
                "version": "v1.0.0",
                "memory_limit_mb": 900,
                "required_memory_mb": 100,
                "target_region": "region-c",
            },
            {
                "name": "beta-under-memory",
                "version": "v2.4.0",
                "memory_limit_mb": 511,
                "required_memory_mb": 512,
                "target_region": "region-b",
            },
            {
                "name": "aardvark-service",
                "version": "release-9",
                "memory_limit_mb": 1024,
                "required_memory_mb": 256,
                "target_region": "region-b",
            },
        ],
    }

    try:
        with open(MANIFEST_PATH, "w") as f:
            json.dump(challenge_manifest, f)
        run_go_program()
        with open(ROSTER_PATH, "r") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"The file {ROSTER_PATH} produced by the Go program is not valid JSON.")

        expected = expected_roster_for(challenge_manifest)
        assert isinstance(actual, list), f"Expected {ROSTER_PATH} to contain a JSON array."
        assert len(actual) == len(expected), f"Expected {len(expected)} services in challenge roster, found {len(actual)}."
        for i in range(len(expected)):
            assert actual[i].get("service") == expected[i]["service"]
            assert actual[i].get("token") == expected[i]["token"]
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
        run_go_program()


def test_roster_exists():
    assert os.path.isfile(ROSTER_PATH), f"The output file {ROSTER_PATH} does not exist. Did you run your Go program?"


def test_roster_content():
    assert os.path.isfile(MANIFEST_PATH), f"The input file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {MANIFEST_PATH} is not valid JSON.")

    allowed_regions = set(manifest.get("global_allowed_regions", []))
    services = manifest.get("services", [])

    expected_roster = []
    for service in services:
        region = service.get("target_region")
        mem_limit = service.get("memory_limit_mb", 0)
        req_mem = service.get("required_memory_mb", 0)

        if region in allowed_regions and mem_limit >= req_mem:
            name = service.get("name", "")
            version = service.get("version", "")

            raw_token = f"{name}:{version}".encode('utf-8')
            encoded_token = base64.b32encode(raw_token).decode('utf-8').rstrip('=')

            expected_roster.append({
                "service": name,
                "token": encoded_token
            })

    expected_roster.sort(key=lambda x: x["service"])

    with open(ROSTER_PATH, 'r') as f:
        try:
            actual_roster = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {ROSTER_PATH} is not valid JSON.")

    assert isinstance(actual_roster, list), f"Expected {ROSTER_PATH} to contain a JSON array."
    assert len(actual_roster) == len(expected_roster), f"Expected {len(expected_roster)} services in roster, found {len(actual_roster)}."

    for i in range(len(expected_roster)):
        expected = expected_roster[i]
        actual = actual_roster[i]

        assert actual.get("service") == expected["service"], f"Expected service name '{expected['service']}' at index {i}, but got '{actual.get('service')}'."
        assert actual.get("token") == expected["token"], f"Expected token '{expected['token']}' for service '{expected['service']}', but got '{actual.get('token')}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
