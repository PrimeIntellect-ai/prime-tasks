#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import string
import subprocess
import pytest

DETECTOR = "/home/user/detector"


def run_detector(token):
    try:
        return subprocess.run(
            [DETECTOR, token],
            capture_output=True,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail("Detector timed out while processing a token")


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector"
    assert os.path.exists(detector_path), f"Detector binary {detector_path} does not exist. Did you compile it?"
    assert os.path.isfile(detector_path), f"{detector_path} is not a file."
    assert os.access(detector_path, os.X_OK), f"Detector binary {detector_path} is not executable."


def test_adversarial_corpus():
    detector_path = "/home/user/detector"
    evil_dir = "/corpus/evil/"
    clean_dir = "/corpus/clean/"

    evil_bypassed = []
    clean_rejected = []

    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} does not exist."
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, 'r') as f:
            content = f.read().strip()
        result = subprocess.run([detector_path, content], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(filename)

    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} does not exist."
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, 'r') as f:
            content = f.read().strip()
        result = subprocess.run([detector_path, content], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_msgs.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_fresh_structural_cases():
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_:-.,/+=@! "

    def random_text(min_len=4, max_len=40):
        return ''.join(rng.choice(alphabet) for _ in range(rng.randint(min_len, max_len)))

    # Active printf conversions exercise the externally controlled format string
    # structurally, including width, length, and positional forms.
    formats = [
        "%n", "%hn", "%hhn", "%ln", "%lln",
        "%s", "%x", "%p", "%08x", "%016x",
        "%1$x", "%2$s", "%3$n", "%7$hn",
    ]

    evil_payloads = []
    for _ in range(120):
        pieces = [random_text()]
        for _ in range(rng.randint(1, 4)):
            pieces.append(rng.choice(formats))
            pieces.append(random_text())
        evil_payloads.append(''.join(pieces))

    # These contain no active conversion. Doubled percent signs are literal
    # percent characters to printf and must not be confused with an exploit.
    clean_payloads = [random_text(8, 90) for _ in range(80)]
    for _ in range(40):
        pieces = [random_text()]
        for _ in range(rng.randint(1, 4)):
            pieces.extend(["%%", random_text()])
        clean_payloads.append(''.join(pieces))

    rng.shuffle(evil_payloads)
    rng.shuffle(clean_payloads)

    failures = []
    for payload in evil_payloads:
        token = base64.b64encode(payload.encode('ascii')).decode('ascii')
        rc = run_detector(token)
        if rc != 1:
            failures.append(f"evil payload accepted (exit {rc}): {payload!r}")
            if len(failures) >= 10:
                break

    for payload in clean_payloads:
        token = base64.b64encode(payload.encode('ascii')).decode('ascii')
        rc = run_detector(token)
        if rc != 0:
            failures.append(f"clean payload rejected (exit {rc}): {payload!r}")
            if len(failures) >= 10:
                break

    if failures:
        pytest.fail("Fresh structural tests failed: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
