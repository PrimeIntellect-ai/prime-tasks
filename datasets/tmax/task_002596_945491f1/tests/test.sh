#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import random
import re
import subprocess
import tempfile

import pytest
import requests

REPO = "/home/user/repo/audio-svc"
EXPECTED_TOKEN = "the quick brown fox jumps over the lazy dog"
URL = "http://127.0.0.1:8080/process"


def expected_smoothing(values):
    result = []
    for original in values:
        value = abs(float(original))
        while value > 0.0:
            value -= 0.1
        result.append(value)
    return result


def assert_numerical_result(payload, response):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        body = response.json()
    except ValueError:
        pytest.fail(f"Service did not return valid JSON. Response body: {response.text}")

    assert "result" in body, f"Response JSON missing 'result' key. Got: {body}"
    assert isinstance(body["result"], list), f"'result' should be a list, got {type(body['result'])}"
    assert len(body["result"]) == len(payload["data"]), "Result list length does not match input data length"

    expected = expected_smoothing(payload["data"])
    for index, (actual, wanted) in enumerate(zip(body["result"], expected)):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
            f"Result element {index} is not numeric: {actual!r}"
        )
        assert math.isfinite(float(actual)), f"Result element {index} is not finite: {actual!r}"
        assert math.isclose(float(actual), wanted, rel_tol=0.0, abs_tol=1e-12), (
            f"Incorrect smoothing result at index {index}: expected {wanted!r}, got {actual!r}"
        )


def post(payload, timeout=5):
    try:
        return requests.post(URL, json=payload, timeout=timeout)
    except requests.exceptions.Timeout:
        pytest.fail("The service timed out. The convergence failure might not be fixed.")
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the service at 127.0.0.1:8080. Is it running?")
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request failed: {exc}")


def test_secret_token():
    token_path = "/home/user/secret_token.txt"
    assert os.path.isfile(token_path), f"Secret token file missing at {token_path}"

    with open(token_path, "r") as handle:
        raw_token = handle.read().strip()
    token = raw_token.lower()

    # Preserve the original punctuation-insensitive assertion.
    import string
    token_clean = token.translate(str.maketrans('', '', string.punctuation))
    expected_clean = EXPECTED_TOKEN.translate(str.maketrans('', '', string.punctuation))
    assert token_clean == expected_clean, (
        f"Secret token is incorrect. Expected '{EXPECTED_TOKEN}', got '{raw_token}'"
    )

    # The instruction additionally requires the exact phrase in lowercase.
    assert raw_token == EXPECTED_TOKEN, (
        f"secret_token.txt must contain the exact lowercase phrase; got {raw_token!r}"
    )


def test_bad_commit_hash():
    commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(commit_file), f"Bad commit file missing at {commit_file}"

    with open(commit_file, "r") as handle:
        actual_commit = handle.read().strip()

    # A full hash is required, preventing the empty-prefix bypass.
    assert re.fullmatch(r"[0-9a-fA-F]{40}", actual_commit), (
        f"bad_commit.txt must contain a full 40-character commit hash, got {actual_commit!r}"
    )

    cmd = ["git", "log", "-G", r"while.*!=.*0\.0", "--format=%H", "--reverse"]
    result = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stderr
    expected_commits = [line for line in result.stdout.strip().splitlines() if line]

    if expected_commits:
        expected_commit = expected_commits[0]
        # Preserve the original full-or-short-prefix assertion, while the format
        # check above enforces the instruction's full-hash requirement.
        assert actual_commit == expected_commit or expected_commit.startswith(actual_commit), (
            f"bad_commit.txt does not contain the correct commit hash. "
            f"Expected {expected_commit}, got {actual_commit}"
        )
    else:
        assert len(actual_commit) >= 7, (
            f"bad_commit.txt does not seem to contain a valid commit hash: {actual_commit}"
        )

    ancestry = subprocess.run(
        ["git", "merge-base", "--is-ancestor", actual_commit, "master"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert ancestry.returncode == 0, "Reported bad commit is not an ancestor of master"

    subject = subprocess.run(
        ["git", "show", "-s", "--format=%s", actual_commit],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    ).stdout.strip()
    assert subject == "Optimize smoothing loop condition", (
        f"Reported commit has unexpected subject: {subject!r}"
    )

    diff = subprocess.run(
        ["git", "show", "--format=", "--unified=0", actual_commit, "--", "src/smoothing.rs"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    ).stdout
    assert re.search(r"^\+\s*while\s+val\s*!=\s*0\.0", diff, re.MULTILINE), (
        "Reported commit does not introduce the non-converging != 0.0 loop"
    )
    assert re.search(r"^-\s*while\s+val\s*>\s*0\.0", diff, re.MULTILINE), (
        "Reported commit does not replace the prior terminating loop condition"
    )


def test_rust_smoothing_source_and_behavior():
    source_path = os.path.join(REPO, "src", "smoothing.rs")
    assert os.path.isfile(source_path), "src/smoothing.rs is missing"
    with open(source_path, "r") as handle:
        source = handle.read()
    assert re.search(r"(?:\.abs\s*\(|f64::abs\s*\()", source), (
        "src/smoothing.rs does not take input values' absolute value"
    )

    rng = random.SystemRandom()
    values = [-1.0, 2.5, -3.2, 0.0]
    values.extend(rng.uniform(-8.0, 8.0) for _ in range(5))
    rust_values = ", ".join(f"{value!r}_f64" for value in values)
    harness = f'''\n#[path = "{source_path}"]\nmod smoothing;\nfn main() {{\n    let output = smoothing::smooth_signal(vec![{rust_values}]);\n    for value in output {{ println!("{{:.17}}", value); }}\n}}\n'''

    with tempfile.TemporaryDirectory() as directory:
        harness_path = os.path.join(directory, "harness.rs")
        binary_path = os.path.join(directory, "harness")
        with open(harness_path, "w") as handle:
            handle.write(harness)
        compiled = subprocess.run(
            ["rustc", "--edition=2021", harness_path, "-o", binary_path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert compiled.returncode == 0, f"Could not compile smoothing.rs:\n{compiled.stderr}"
        try:
            executed = subprocess.run(
                [binary_path], capture_output=True, text=True, timeout=5, check=True
            )
        except subprocess.TimeoutExpired:
            pytest.fail("smooth_signal hangs on negative input")

    lines = executed.stdout.strip().splitlines()
    assert len(lines) == len(values), f"smooth_signal returned the wrong number of values: {lines!r}"
    try:
        actual = [float(line) for line in lines]
    except ValueError:
        pytest.fail(f"smooth_signal produced non-numeric output: {lines!r}")

    for index, (got, wanted) in enumerate(zip(actual, expected_smoothing(values))):
        assert math.isclose(got, wanted, rel_tol=0.0, abs_tol=1e-12), (
            f"src/smoothing.rs is incorrect at index {index}: expected {wanted!r}, got {got!r}"
        )


def listener_pids():
    socket_inodes = set()
    with open("/proc/net/tcp", "r") as handle:
        for line in handle.read().splitlines()[1:]:
            fields = line.split()
            if len(fields) > 9 and fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                socket_inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def test_deployed_service_is_repository_binary():
    # First establish that something is listening and responsive.
    response = post({"token": EXPECTED_TOKEN, "data": [-0.37]}, timeout=5)
    assert response.status_code == 200, response.text

    pids = listener_pids()
    assert pids, "No process is listening specifically on 127.0.0.1:8080"

    allowed = {
        os.path.realpath(os.path.join(REPO, "target", "debug", "audio-svc")): [],
        os.path.realpath(os.path.join(REPO, "target", "release", "audio-svc")): ["--release"],
    }

    matched = None
    for pid in pids:
        try:
            link = os.readlink(f"/proc/{pid}/exe")
        except OSError:
            continue
        assert not link.endswith(" (deleted)"), "The listening service executable is stale or deleted"
        real_exe = os.path.realpath(f"/proc/{pid}/exe")
        if real_exe in allowed:
            matched = (pid, real_exe, allowed[real_exe])
            break

    assert matched is not None, (
        "The listener is not the audio-svc executable built in this repository's target directory"
    )
    pid, executable, profile_args = matched

    built = subprocess.run(
        ["cargo", "build", *profile_args],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert built.returncode == 0, f"The repository does not compile:\n{built.stderr}"
    assert os.path.isfile(executable), f"Expected Cargo artifact is missing: {executable}"
    assert sha256(f"/proc/{pid}/exe") == sha256(executable), (
        "The running listener does not match the service compiled from the current repository"
    )


def test_service_processing_and_authentication():
    fixed_payload = {
        "token": EXPECTED_TOKEN,
        "data": [-1.0, 2.5, -3.2],
    }
    assert_numerical_result(fixed_payload, post(fixed_payload))

    rng = random.SystemRandom()
    dynamic_values = [rng.uniform(-20.0, 20.0) for _ in range(7)]
    dynamic_values.extend([0.0, -0.05, 0.15])
    dynamic_payload = {"token": EXPECTED_TOKEN, "data": dynamic_values}
    assert_numerical_result(dynamic_payload, post(dynamic_payload))

    for invalid_payload in (
        {"token": "wrong token", "data": [-1.0, 2.5, -3.2]},
        {"token": EXPECTED_TOKEN + " ", "data": [-1.0]},
        {"data": [-1.0]},
    ):
        response = post(invalid_payload)
        assert not (200 <= response.status_code < 300), (
            f"Service accepted an invalid or missing authentication token: {invalid_payload!r}; "
            f"response was {response.status_code} {response.text!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
