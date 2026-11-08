#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VALIDATOR_SCRIPT = "/home/user/validator.py"
START_SCRIPT = "/home/user/start_pipeline.sh"


def run_validator(path):
    return subprocess.run(
        ["python3", VALIDATOR_SCRIPT, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_validator_script_exists():
    assert os.path.isfile(VALIDATOR_SCRIPT), f"Validator script {VALIDATOR_SCRIPT} does not exist."


def test_start_script_exists_and_executable():
    assert os.path.isfile(START_SCRIPT), f"Start script {START_SCRIPT} does not exist."
    assert os.access(START_SCRIPT, os.X_OK), f"Start script {START_SCRIPT} is not executable."


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for path in clean_files:
        if run_validator(path) != 0:
            clean_failures.append(os.path.basename(path))

    evil_failures = []
    for path in evil_files:
        if run_validator(path) == 0:
            evil_failures.append(os.path.basename(path))

    error_msg = []
    if clean_failures:
        error_msg.append(
            f"{len(clean_failures)} of {len(clean_files)} clean files rejected: "
            f"{', '.join(clean_failures[:5])}"
        )
    if evil_failures:
        error_msg.append(
            f"{len(evil_failures)} of {len(evil_files)} evil files bypassed: "
            f"{', '.join(evil_failures[:5])}"
        )

    assert not error_msg, " | ".join(error_msg)


def valid_csv(rng, row_count):
    lines = ["epoch,loss,accuracy"]
    for _ in range(row_count):
        epoch = rng.randrange(0, 1000000)
        loss = rng.uniform(0.000001, 1000.0)
        accuracy = rng.uniform(0.0, 1.0)
        lines.append(f"{epoch},{loss:.9f},{accuracy:.9f}")
    return "\n".join(lines) + "\n"


def test_validator_on_fresh_randomized_inputs():
    rng = random.SystemRandom()
    cases = []

    for _ in range(10):
        cases.append((valid_csv(rng, rng.randrange(1, 12)), True))

    # Inclusive accuracy boundaries are valid, and epochs need only be non-negative integers.
    cases.append(("epoch,loss,accuracy\n42,0.25,0.0\n7,3.5,1.0\n", True))

    loss = rng.uniform(0.1, 10.0)
    accuracy = rng.uniform(0.1, 0.9)
    invalid = [
        f"epoch,loss\n1,{loss:.8f}\n",
        f"epoch,loss,accuracy,extra\n1,{loss:.8f},{accuracy:.8f},x\n",
        f"epoch,loss,accuracy,accuracy\n1,{loss:.8f},{accuracy:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n-1,{loss:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1.5,{loss:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\nnot_an_int,{loss:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,0,{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,-{loss:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,not_a_float,{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,,{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,nan,{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},-0.01\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},1.01\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},not_a_float\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},nan\n",
        f"epoch,loss,accuracy\n,{loss:.8f},{accuracy:.8f}\n",
        f"epoch,loss,accuracy\n1,{loss:.8f},{accuracy:.8f},\n",
    ]
    cases.extend((content, False) for content in invalid)
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="validator-random-") as directory:
        for content, expected_clean in cases:
            path = os.path.join(directory, secrets.token_hex(16) + ".csv")
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(content)
            accepted = run_validator(path) == 0
            if accepted != expected_clean:
                failures.append(
                    f"expected {'accept' if expected_clean else 'reject'} for {content!r}"
                )

    assert not failures, "Validator failed fresh generated cases: " + " | ".join(failures[:5])


def multipart_request(url, payload):
    boundary = "----VerifierBoundary" + uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="upload.csv"\r\n'
        "Content-Type: text/csv\r\n\r\n"
    ).encode("ascii") + payload + f"\r\n--{boundary}--\r\n".encode("ascii")
    return urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )


def test_end_to_end_pipeline():
    subprocess.run([START_SCRIPT], shell=True, check=True)
    time.sleep(2)

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    assert len(clean_files) > 0, "No clean files found for e2e test."
    with open(clean_files[0], "rb") as handle:
        clean_data = handle.read()

    req = multipart_request("http://127.0.0.1:8080/upload", clean_data)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            assert response.status == 200, f"Expected HTTP 200 for clean file, got {response.status}"
    except urllib.error.HTTPError as exc:
        pytest.fail(f"HTTP request failed for clean file: {exc.code} {exc.reason}")
    except urllib.error.URLError as exc:
        pytest.fail(f"Connection failed: {exc.reason}. Is Nginx and Flask running on port 8080?")

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert len(evil_files) > 0, "No evil files found for e2e test."
    with open(evil_files[0], "rb") as handle:
        evil_data = handle.read()

    req = multipart_request("http://127.0.0.1:8080/upload", evil_data)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            pytest.fail(f"Expected HTTP 400 for evil file, got {response.status}")
    except urllib.error.HTTPError as exc:
        assert exc.code == 400, f"Expected HTTP 400 for evil file, got {exc.code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
