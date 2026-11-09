#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import uuid


def test_spike_frames_extracted():
    """Verify that the correct frame numbers were extracted and saved."""
    file_path = "/home/user/spike_frames.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Task 1 was not completed."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_frames = "145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160"
    assert content == expected_frames, f"Extracted frames do not match the expected output. Got: '{content}'"


def run_filter(script_path, directory):
    return subprocess.run(
        ["python3", script_path, directory],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_cost_filter_adversarial_corpus():
    """Preserve the original corpus checks."""
    script_path = "/home/user/cost_filter.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing. Task 2 was not completed."

    evil_corpus_path = "/app/corpora/evil/"
    clean_corpus_path = "/app/corpora/clean/"

    assert os.path.isdir(evil_corpus_path), f"Evil corpus path {evil_corpus_path} is missing."
    assert os.path.isdir(clean_corpus_path), f"Clean corpus path {clean_corpus_path} is missing."

    evil_dirs = [os.path.join(evil_corpus_path, d) for d in os.listdir(evil_corpus_path) if os.path.isdir(os.path.join(evil_corpus_path, d))]
    clean_dirs = [os.path.join(clean_corpus_path, d) for d in os.listdir(clean_corpus_path) if os.path.isdir(os.path.join(clean_corpus_path, d))]

    evil_bypassed = []
    for d in evil_dirs:
        result = run_filter(script_path, d)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            evil_bypassed.append(os.path.basename(d))

    clean_modified = []
    for d in clean_dirs:
        result = run_filter(script_path, d)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            clean_modified.append(os.path.basename(d))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_dirs)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_dirs)} clean modified: {', '.join(clean_modified)}")

    assert not evil_bypassed and not clean_modified, " ; ".join(error_messages)


def policy_result(directory):
    """Independently derive the required result from the generated payload."""
    forbidden_extensions = {".dump", ".iso", ".mp4"}
    marker = b"[COST_ALERT: MASSIVE_LOG]"
    for root, _, files in os.walk(directory):
        for name in files:
            path = os.path.join(root, name)
            if os.path.getsize(path) > 100000:
                return "REJECT", 1
            if os.path.splitext(name)[1] in forbidden_extensions:
                return "REJECT", 1
            with open(path, "rb") as handle:
                if marker in handle.read():
                    return "REJECT", 1
    return "ACCEPT", 0


def test_cost_filter_on_unpredictable_generated_payloads():
    """Exercise the actual recursive policy at paths unknown to the submission."""
    script_path = "/home/user/cost_filter.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing. Task 2 was not completed."

    base = tempfile.mkdtemp(prefix=".cf_", dir="/tmp")
    payloads = []

    def new_payload():
        path = os.path.join(base, uuid.uuid4().hex)
        os.makedirs(path)
        payloads.append(path)
        return path

    def nested(payload):
        path = payload
        for _ in range(secrets.randbelow(3) + 2):
            path = os.path.join(path, uuid.uuid4().hex)
        os.makedirs(path, exist_ok=True)
        return path

    def write_file(payload, data, suffix=".txt"):
        path = os.path.join(nested(payload), uuid.uuid4().hex + suffix)
        with open(path, "wb") as handle:
            handle.write(data)

    try:
        # Clean empty and nested payloads, including the exact size boundary.
        new_payload()
        clean_boundary = new_payload()
        write_file(clean_boundary, b"A" * 100000, ".bin")
        write_file(clean_boundary, b"ordinary log data", ".log")

        # One independently hidden payload for each rejection rule.
        oversized = new_payload()
        write_file(oversized, os.urandom(100001), ".dat")

        for extension in (".dump", ".iso", ".mp4"):
            forbidden = new_payload()
            write_file(forbidden, b"", extension)

        marked = new_payload()
        write_file(marked, b"\xff\xfe-prefix-[COST_ALERT: MASSIVE_LOG]-suffix\x00", ".log")

        # Additional randomized combinations prevent classification by test order.
        for _ in range(10):
            payload = new_payload()
            write_file(payload, os.urandom(secrets.randbelow(2048)), ".data")
            choice = secrets.randbelow(5)
            if choice == 1:
                write_file(payload, b"Z" * 100001, ".blob")
            elif choice == 2:
                write_file(payload, b"small", random.choice([".dump", ".iso", ".mp4"]))
            elif choice == 3:
                write_file(payload, b"before[COST_ALERT: MASSIVE_LOG]after", ".txt")
            elif choice == 4:
                write_file(payload, b"Z" * 100000, ".blob")

        expected = [(path, *policy_result(path)) for path in payloads]
        assert any(item[1] == "ACCEPT" for item in expected)
        assert any(item[1] == "REJECT" for item in expected)
        random.SystemRandom().shuffle(expected)

        failures = []
        for path, expected_output, expected_code in expected:
            result = run_filter(script_path, path)
            actual_output = result.stdout.strip()
            if result.returncode != expected_code or actual_output != expected_output:
                failures.append(
                    f"payload {os.path.basename(path)}: expected output/status "
                    f"{expected_output}/{expected_code}, got {actual_output!r}/{result.returncode}"
                )
        assert not failures, " ; ".join(failures)
    finally:
        shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
