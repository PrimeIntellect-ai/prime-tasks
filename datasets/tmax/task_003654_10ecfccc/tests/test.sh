#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/classifier.sh"


def run_classifier(path):
    try:
        return subprocess.run(
            ["/bin/bash", SCRIPT_PATH, path],
            capture_output=True,
            timeout=2,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_classifier_exists_and_executable():
    script_path = "/home/user/classifier.sh"
    assert os.path.exists(script_path), f"Missing script: {script_path}"
    assert os.path.isfile(script_path), f"Not a file: {script_path}"


def test_adversarial_corpus():
    script_path = "/home/user/classifier.sh"
    evil_dir = "/home/user/artifacts/evil/"
    clean_dir = "/home/user/artifacts/clean/"

    assert os.path.isdir(evil_dir), f"Missing evil directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean directory: {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    bypassed_evil = []
    for f in evil_files:
        filepath = os.path.join(evil_dir, f)
        result = run_classifier(filepath)
        if result == 0:
            bypassed_evil.append(f)
        elif result is None:
            bypassed_evil.append(f + " (timed out)")

    modified_clean = []
    for f in clean_files:
        filepath = os.path.join(clean_dir, f)
        result = run_classifier(filepath)
        if result != 0:
            modified_clean.append(f if result is not None else f + " (timed out)")

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def oracle_is_safe(blob):
    try:
        if blob.startswith(b"\xff\xfe"):
            header = blob[2:130].decode("utf-16-le").split("\x00", 1)[0]
        else:
            header = blob[:64].split(b"\x00", 1)[0].decode("utf-8")
        value = json.loads(header)
        data_size = value["data_size"]
        if not isinstance(data_size, int) or isinstance(data_size, bool):
            return False
    except (UnicodeError, ValueError, KeyError, TypeError):
        return False

    # This is the boundary used by artifact_reader before its crashing path.
    return not (data_size > 0 and data_size > len(blob) * 2)


def encode_artifact(encoding, data_size, payload):
    text = json.dumps({"data_size": data_size}, separators=(",", ":"))
    assert len(text) <= 64
    padded = text.ljust(64, "\x00")
    if encoding == "utf16":
        header = b"\xff\xfe" + padded.encode("utf-16-le")
    else:
        header = padded.encode("utf-8")
    return header + payload


def test_randomized_unlabelled_artifacts():
    rng = random.SystemRandom()
    cases = []

    # Generate both encodings and values on both sides of the actual-size
    # boundary. Names and paths contain no clean/evil signal.
    for encoding in ("utf8", "utf16"):
        header_size = 64 if encoding == "utf8" else 130
        for _ in range(5):
            payload_size = rng.randint(96, 4096)
            total_size = header_size + payload_size
            payload = os.urandom(payload_size)

            safe_size = max(1, 2 * total_size - rng.randint(0, 31))
            safe_blob = encode_artifact(encoding, safe_size, payload)
            cases.append((safe_blob, oracle_is_safe(safe_blob)))

            evil_size = 2 * total_size + rng.randint(1, 31)
            evil_blob = encode_artifact(encoding, evil_size, payload)
            cases.append((evil_blob, oracle_is_safe(evil_blob)))

            ordinary_blob = encode_artifact(encoding, payload_size, payload)
            cases.append((ordinary_blob, oracle_is_safe(ordinary_blob)))

    # Explicit malformed JSON cases are required to be rejected.
    for encoding in ("utf8", "utf16"):
        bad_text = "{this is not valid json}".ljust(64, "\x00")
        header = bad_text.encode("utf-8")
        if encoding == "utf16":
            header = b"\xff\xfe" + bad_text.encode("utf-16-le")
        blob = header + os.urandom(rng.randint(64, 512))
        cases.append((blob, oracle_is_safe(blob)))

    assert any(expected for _, expected in cases)
    assert any(not expected for _, expected in cases)
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=".artifact-check-") as case_dir:
        for blob, expected_safe in cases:
            path = os.path.join(case_dir, uuid.uuid4().hex)
            with open(path, "wb") as artifact:
                artifact.write(blob)

            returncode = run_classifier(path)
            assert returncode is not None, "classifier timed out on a generated artifact"
            if expected_safe:
                assert returncode == 0, "classifier rejected a generated safe artifact"
            else:
                assert returncode != 0, "classifier accepted a generated malicious or malformed artifact"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
