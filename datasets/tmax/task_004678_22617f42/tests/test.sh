#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
FILTER_BIN = "/home/user/spectro_filter"
FILTER_SOURCE = "/home/user/spectro_filter.go"
API_URL = "http://127.0.0.1:8000/ingest"


def run_filter(filepath):
    result = subprocess.run(
        [FILTER_BIN, filepath],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
    return result.returncode


def expected_result(spectrum):
    x = spectrum["x"]
    y = spectrum["y"]
    indices = list(range(50)) + list(range(950, 1000))
    bx = [x[i] for i in indices]
    by = [y[i] for i in indices]

    mean_x = sum(bx) / len(bx)
    mean_y = sum(by) / len(by)
    denominator = sum((v - mean_x) ** 2 for v in bx)
    numerator = sum((vx - mean_x) * (vy - mean_y) for vx, vy in zip(bx, by))
    slope = numerator / denominator

    variance = sum((v - mean_y) ** 2 for v in by) / (len(by) - 1)
    sample_stddev = math.sqrt(variance)
    absolute_peak = max(abs(v) for v in y)

    rejected = abs(slope) > 0.05 or absolute_peak < mean_y + 5 * sample_stddev
    return 1 if rejected else 0


def make_generated_cases():
    rng = random.Random(secrets.randbits(128))
    cases = []

    for mode in (["valid"] * 8 + ["drift"] * 8 + ["no_peak"] * 8):
        start = rng.uniform(-2.0, 2.0)
        x = [start]
        for _ in range(999):
            x.append(x[-1] + rng.uniform(0.005, 0.02))

        if mode == "no_peak":
            y = [rng.uniform(-0.006, 0.006) for _ in range(1000)]
        else:
            if mode == "valid":
                slope = rng.uniform(-0.03, 0.03)
            else:
                slope = rng.choice([-1.0, 1.0]) * rng.uniform(0.075, 0.12)

            intercept = rng.uniform(-0.03, 0.03)
            y = [rng.uniform(-0.004, 0.004) for _ in range(1000)]
            for i in list(range(50)) + list(range(950, 1000)):
                y[i] = intercept + slope * x[i] + rng.uniform(-0.001, 0.001)
            y[rng.randrange(100, 900)] = rng.choice([-10.0, 10.0])

        spectrum = {"x": x, "y": y}
        expected = expected_result(spectrum)
        intended = 0 if mode == "valid" else 1
        assert expected == intended, f"Internal generated case was not {mode} as intended"
        cases.append((spectrum, expected))

    rng.shuffle(cases)
    return cases


@pytest.fixture(scope="session")
def generated_cases():
    return make_generated_cases()


def post_spectrum(spectrum):
    data = json.dumps(spectrum).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            body = response.read()
            assert response.status == 200
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to send request to ingestion API: {exc}")
    try:
        return json.loads(body)
    except Exception as exc:
        pytest.fail(f"Ingestion API returned invalid JSON: {exc}")


def test_go_artifacts_exist_and_are_go_binary():
    assert os.path.isfile(FILTER_SOURCE), f"Go source not found at {FILTER_SOURCE}"
    assert os.path.isfile(FILTER_BIN), f"Go binary not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"Go binary at {FILTER_BIN} is not executable"
    result = subprocess.run(
        ["go", "version", "-m", FILTER_BIN],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0 and "go1" in result.stdout, (
        f"{FILTER_BIN} does not appear to be a compiled Go binary"
    )


def test_go_binary_adversarial_corpus():
    """Retain the original direct checks against the provided corpora."""
    assert os.path.isfile(FILTER_BIN), f"Go binary not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"Go binary at {FILTER_BIN} is not executable"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_modified = []
    for cf in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, cf)
        if run_filter(filepath) != 0:
            clean_modified.append(cf)

    evil_bypassed = []
    for ef in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, ef)
        if run_filter(filepath) != 1:
            evil_bypassed.append(ef)

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_go_binary_generated_inputs(generated_cases):
    """Exercise unseen spectra at neutral randomized paths with independently derived answers."""
    with tempfile.TemporaryDirectory(prefix="spectra_") as directory:
        for index, (spectrum, expected) in enumerate(generated_cases):
            path = os.path.join(directory, f"sample_{secrets.token_hex(8)}_{index}.json")
            with open(path, "w") as handle:
                json.dump(spectrum, handle)
            actual = run_filter(path)
            assert actual == expected, f"Generated spectrum {index}: expected exit {expected}, got {actual}"


def test_multi_service_composition():
    """Retain the original end-to-end corpus and Redis assertion."""
    try:
        subprocess.run(["redis-cli", "DEL", "valid_spectra"], check=True, capture_output=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to connect to Redis or execute DEL command. Is Redis running?")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]

    for cf in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, cf)
        with open(filepath, 'rb') as f:
            data = f.read()
        req = urllib.request.Request(API_URL, data=data, headers={'Content-Type': 'application/json'})
        try:
            urllib.request.urlopen(req, timeout=10).close()
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to send request to ingestion API: {e}")

    for ef in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, ef)
        with open(filepath, 'rb') as f:
            data = f.read()
        req = urllib.request.Request(API_URL, data=data, headers={'Content-Type': 'application/json'})
        try:
            urllib.request.urlopen(req, timeout=10).close()
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to send request to ingestion API: {e}")

    result = subprocess.run(["redis-cli", "LLEN", "valid_spectra"], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail("Failed to query Redis for valid_spectra length.")
    try:
        llen = int(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Unexpected output from Redis LLEN: {result.stdout}")
    assert llen == len(clean_files), f"Expected {len(clean_files)} items in Redis list 'valid_spectra', but found {llen}."


def test_multi_service_generated_inputs(generated_cases):
    """Verify API decisions and exact Redis routing for unseen generated spectra."""
    subprocess.run(["redis-cli", "DEL", "valid_spectra"], check=True, capture_output=True)
    accepted = []

    for index, (spectrum, expected) in enumerate(generated_cases):
        response = post_spectrum(spectrum)
        expected_status = "accepted" if expected == 0 else "rejected"
        assert response.get("status") == expected_status, (
            f"Generated API spectrum {index}: expected {expected_status}, got {response}"
        )
        if expected == 0:
            accepted.append(spectrum)

    result = subprocess.run(
        ["redis-cli", "--raw", "LRANGE", "valid_spectra", "0", "-1"],
        check=True,
        capture_output=True,
        text=True,
    )
    stored_lines = result.stdout.splitlines() if result.stdout else []
    assert len(stored_lines) == len(accepted), (
        f"Expected {len(accepted)} generated valid spectra in Redis, found {len(stored_lines)}"
    )
    stored = [json.loads(line) for line in stored_lines]
    assert stored == accepted, "Redis did not contain exactly the generated spectra accepted by the filter"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
