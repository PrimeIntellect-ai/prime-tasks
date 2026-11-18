#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

DETECTOR = "/home/user/detector.py"
KEY = bytes([0x4B, 0x1D, 0xEC, 0xAF])


def encode(text):
    raw = text.encode("utf-8")
    obfuscated = bytes(value ^ KEY[index % len(KEY)] for index, value in enumerate(raw))
    return base64.b64encode(obfuscated).decode("ascii")


def test_detector_script_exists():
    detector_script = "/home/user/detector.py"
    assert os.path.exists(detector_script), f"Detector script not found at {detector_script}"
    assert os.path.isfile(detector_script), f"Detector path is not a file: {detector_script}"


def test_detector_evil_corpus():
    detector_script = "/home/user/detector.py"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(evil_dir), f"Evil corpus directory not found: {evil_dir}"

    evil_files = sorted([f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))])
    assert len(evil_files) > 0, "Evil corpus directory is empty"

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(["python3", detector_script, filepath], capture_output=True, text=True)

        # Must exit with code 1 and print EVIL
        if result.returncode != 1 or "EVIL" not in result.stdout:
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_detector_clean_corpus():
    detector_script = "/home/user/detector.py"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(clean_dir), f"Clean corpus directory not found: {clean_dir}"

    clean_files = sorted([f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))])
    assert len(clean_files) > 0, "Clean corpus directory is empty"

    modified = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(["python3", detector_script, filepath], capture_output=True, text=True)

        # Must exit with code 0 and print CLEAN
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            modified.append(filename)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified: {', '.join(modified)}")


def test_detector_randomized_hidden_corpus():
    # Every sample uses the same unlabeled directory and an unrelated random name,
    # so classification cannot be inferred from the argument path.
    corpus_dir = tempfile.mkdtemp(prefix="csp-check-")
    cases = []
    try:
        for index in range(240):
            should_be_evil = bool(secrets.randbits(1))
            noise = secrets.token_hex(random.randint(3, 25))

            if should_be_evil:
                prefix = secrets.token_hex(random.randint(0, 12))
                key_kind = random.choice(["OPENSSH", "RSA", "EC"])
                plaintext = (
                    prefix
                    + f"-----BEGIN {key_kind} PRIVATE KEY-----\n"
                    + noise
                    + f"\n-----END {key_kind} PRIVATE KEY-----"
                )
                directive = "exfil-" + encode(plaintext)
            elif index % 3:
                harmless = random.choice([
                    f"Harmless diagnostic payload {noise}",
                    f"PRIVATE material but no key marker {noise}",
                    f"Public key report only {noise}",
                    f"Decoy exfiltration message {noise}",
                ])
                directive = "exfil-" + encode(harmless)
            else:
                directive = random.choice([
                    "default-src 'self'",
                    "script-src 'none'",
                    "img-src https: data:",
                ])

            report = {
                "csp-report": {
                    "document-uri": f"https://{noise[:8]}.example.invalid/page",
                    "blocked-uri": "inline",
                    "violated-directive": directive,
                    "original-policy": "default-src 'self'",
                }
            }
            filename = secrets.token_hex(16) + ".json"
            filepath = os.path.join(corpus_dir, filename)
            with open(filepath, "w", encoding="utf-8") as handle:
                json.dump(report, handle, separators=(",", ":"))
            cases.append((filepath, should_be_evil))

        random.SystemRandom().shuffle(cases)
        failures = []
        for filepath, should_be_evil in cases:
            result = subprocess.run(
                ["python3", DETECTOR, filepath],
                capture_output=True,
                text=True,
                timeout=10,
            )
            expected_code = 1 if should_be_evil else 0
            expected_text = "EVIL" if should_be_evil else "CLEAN"
            if result.returncode != expected_code or expected_text not in result.stdout:
                failures.append(os.path.basename(filepath))

        if failures:
            pytest.fail(
                f"{len(failures)} of {len(cases)} randomized hidden cases were misclassified: "
                + ", ".join(failures[:10])
            )
    finally:
        shutil.rmtree(corpus_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
