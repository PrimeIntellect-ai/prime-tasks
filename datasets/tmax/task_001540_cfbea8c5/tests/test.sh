#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import urllib.parse
import pytest

DETECTOR = "/home/user/detector.sh"


def run_detector(value):
    try:
        result = subprocess.run(
            ["bash", DETECTOR],
            input=value.encode("utf-8"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Detector did not terminate within 5 seconds")
    return result.returncode


def mixed_case(value):
    return "".join(
        ch.upper() if ch.isalpha() and secrets.randbits(1) else ch.lower() if ch.isalpha() else ch
        for ch in value
    )


def test_recovered_payloads():
    path = "/home/user/recovered_payloads.txt"
    assert os.path.exists(path), f"Recovered payloads file is missing at {path}"

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_payloads = [
        "<sCrIpt>alert(document.domain)</script>",
        "admin' OR 1=1--",
        "\"><svg/onload=prompt(1)>"
    ]

    for payload in expected_payloads:
        assert payload in content, f"Missing expected payload in {path}: {payload}"


def test_detector_script_exists_and_executable():
    path = DETECTOR
    assert os.path.exists(path), f"Detector script is missing at {path}"
    assert os.path.isfile(path), f"Detector path is not a regular file: {path}"
    assert os.access(path, os.X_OK), f"Detector script at {path} is not marked as executable"


def test_adversarial_corpus():
    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_bypassed = []
    clean_modified = []

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."
    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        with open(file_path, "rb") as stdin_f:
            res = subprocess.run(["bash", DETECTOR], stdin=stdin_f)
            if res.returncode != 1:
                evil_bypassed.append(f)

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."
    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        with open(file_path, "rb") as stdin_f:
            res = subprocess.run(["bash", DETECTOR], stdin=stdin_f)
            if res.returncode != 0:
                clean_modified.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, "Adversarial corpus verification failed:\n" + "\n".join(errors)


def test_generated_adversarial_inputs():
    malicious_templates = [
        "<script>alert(document.domain)</script>",
        "\"><svg/onload=prompt(1)>",
        "<img src=x onerror=alert(1)>",
        "javascript:alert(1)",
        "admin' OR 1=1--",
        "' OR 'x'='x' --",
        "' UNION SELECT username,password FROM users--",
        "1; DROP TABLE users;--",
    ]

    generated = []
    for template in malicious_templates:
        randomized = mixed_case(template)
        padding = " " * (1 + secrets.randbelow(4))
        generated.extend([
            template,
            randomized,
            padding + randomized + padding,
            urllib.parse.quote(randomized, safe=""),
        ])

    bypassed = []
    for value in generated:
        if run_detector(value) != 1:
            bypassed.append(value)

    assert not bypassed, "Detector accepted generated malicious inputs: " + repr(bypassed)


def test_generated_benign_inputs():
    benign = [
        "Alice Example",
        "O'Reilly is a publisher.",
        "Just a normal text message.",
        "<b>Hello</b>",
        "https://example.com/search?q=flowers%20and%20trees",
        "Please select a delivery date from the menu.",
        "The union meeting starts at noon.",
        "Drop the package at the front desk.",
        "john_doe-42",
    ]

    generated = []
    for value in benign:
        padding = " " * (1 + secrets.randbelow(4))
        generated.extend([value, padding + value + padding])

    rejected = []
    for value in generated:
        if run_detector(value) != 0:
            rejected.append(value)

    assert not rejected, "Detector rejected generated benign inputs: " + repr(rejected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
