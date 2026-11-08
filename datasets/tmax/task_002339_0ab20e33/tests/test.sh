#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import time
import urllib.request
from urllib.error import HTTPError, URLError

import pytest

WORKSPACE = "/home/user/workspace"
ARTIFACT_DIR = f"{WORKSPACE}/artifacts"
SCRIPT = f"{WORKSPACE}/verify_and_route.sh"
CONF = f"{WORKSPACE}/nginx.conf"
FILENAMES = [
    "build_alpha.tar",
    "build_beta.tar",
    "build_gamma.tar",
    "build_delta.tar",
]


def get_parity(filename, size):
    ascii_sum = sum(ord(c) for c in filename)
    return (size ^ ascii_sum) % 251


def wait_for_url(url, expected_codes, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            req = urllib.request.Request(url, method="HEAD")
            with urllib.request.urlopen(req, timeout=1) as response:
                if response.status in expected_codes:
                    return response.status
                last_error = AssertionError(f"Unexpected HTTP status {response.status}")
        except HTTPError as exc:
            if exc.code in expected_codes:
                return exc.code
            last_error = exc
        except URLError as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f"Timed out waiting for {url}: {last_error}")


@pytest.fixture(scope="session")
def prepared_state():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    # Eliminate services/configuration left behind before actually exercising the script.
    subprocess.run(["pkill", "-x", "nginx"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-u", "user"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    for path in (CONF, f"{WORKSPACE}/nginx.pid", f"{WORKSPACE}/nginx_error.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Create a fresh, unpredictable challenge so a canned configuration cannot pass.
    rng = secrets.SystemRandom()
    sizes = rng.sample(range(4096, 24000), len(FILENAMES))
    valid_names = set(rng.sample(FILENAMES, 2))
    expected_bodies = {}
    entries = []
    expected_status = {}

    for filename, size in zip(FILENAMES, sizes):
        body = os.urandom(size)
        expected_bodies[filename] = body
        with open(os.path.join(ARTIFACT_DIR, filename), "wb") as artifact:
            artifact.write(body)

        actual = get_parity(filename, size)
        if filename in valid_names:
            claimed = actual
            expected_status[filename] = 200
        else:
            claimed = (actual + rng.randint(1, 250)) % 251
            expected_status[filename] = 403
        entries.append({"filename": filename, "expected_parity": claimed})

    challenge_manifest = {"artifacts": entries}
    manifest_path = os.path.join(ARTIFACT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as manifest_file:
        json.dump(challenge_manifest, manifest_file)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT],
        cwd=WORKSPACE,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"Script exited with status {result.returncode}"

    assert os.path.isfile(CONF), f"Nginx configuration {CONF} does not exist."
    syntax = subprocess.run(
        ["nginx", "-t", "-c", CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    assert syntax.returncode == 0, f"Generated Nginx configuration is invalid:\n{syntax.stdout}"

    # The script must not evade the challenge by deleting or rewriting its inputs.
    with open(manifest_path, "r", encoding="utf-8") as manifest_file:
        assert json.load(manifest_file) == challenge_manifest
    for filename, body in expected_bodies.items():
        path = os.path.join(ARTIFACT_DIR, filename)
        assert os.path.isfile(path), f"Artifact {filename} was removed"
        assert os.path.getsize(path) == len(body), f"Artifact {filename} was modified"

    wait_for_url("http://127.0.0.1:9000/build_alpha.tar", {200})
    for filename, status in expected_status.items():
        wait_for_url(f"http://127.0.0.1:8080/download/{filename}", {status})

    return expected_bodies, expected_status


def test_python_backend_running(prepared_state):
    expected_bodies, _ = prepared_state
    for filename, expected_body in expected_bodies.items():
        url = f"http://127.0.0.1:9000/{filename}"
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                assert response.status == 200
                assert response.read() == expected_body
        except HTTPError as exc:
            pytest.fail(f"Python backend returned HTTP {exc.code} for {filename}")
        except URLError as exc:
            pytest.fail(f"Could not connect to Python backend on port 9000: {exc.reason}")


def test_nginx_routing(prepared_state):
    expected_bodies, expected_status = prepared_state
    for filename, wanted_status in expected_status.items():
        url = f"http://127.0.0.1:8080/download/{filename}"
        if wanted_status == 200:
            try:
                with urllib.request.urlopen(url, timeout=2) as response:
                    assert response.status == 200
                    assert response.read() == expected_bodies[filename], \
                        f"Nginx did not proxy the contents of {filename}"
            except HTTPError as exc:
                pytest.fail(f"Expected 200 for valid artifact {filename}, got HTTP {exc.code}")
            except URLError as exc:
                pytest.fail(f"Could not connect to Nginx on port 8080: {exc.reason}")
        else:
            try:
                with urllib.request.urlopen(url, timeout=2) as response:
                    pytest.fail(f"Expected 403 for corrupted artifact {filename}, got {response.status}")
            except HTTPError as exc:
                assert exc.code == 403, \
                    f"Expected 403 for corrupted artifact {filename}, got HTTP {exc.code}"
            except URLError as exc:
                pytest.fail(f"Could not connect to Nginx on port 8080: {exc.reason}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
