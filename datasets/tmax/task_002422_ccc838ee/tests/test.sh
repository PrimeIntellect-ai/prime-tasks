#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import io
import os
import random
import secrets
import subprocess
import tempfile

import pytest
from PIL import Image


def test_extracted_seed():
    seed_file = "/home/user/extracted_seed.txt"
    assert os.path.exists(seed_file), f"Seed file missing: {seed_file}"

    with open(seed_file, "r") as f:
        content = f.read()

    assert "8x9F2a_poly" in content, f"Extracted seed is incorrect. Found: {content.strip()}"


def test_filter_script_exists():
    script_path = "/home/user/filter.py"
    assert os.path.exists(script_path), f"Filter script missing: {script_path}"
    assert os.path.isfile(script_path), f"Filter script is not a file: {script_path}"


def test_adversarial_corpus():
    script_path = "/home/user/filter.py"
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(script_path), f"Script not found at {script_path}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_rejected = []

    for fpath in evil_files:
        result = subprocess.run(["python3", script_path, fpath], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(fpath))

    for fpath in clean_files:
        result = subprocess.run(["python3", script_path, fpath], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(fpath))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}")
    if clean_rejected:
        error_msgs.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {clean_rejected}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_filter_uses_file_content_not_path():
    script_path = "/home/user/filter.py"
    payloads = [
        b"\x7fELF",
        b"../../../../etc/shadow",
        b"<script>alert(1)</script>",
    ]

    with tempfile.TemporaryDirectory(prefix="classifier_cases_") as root:
        misleading_evil_dir = os.path.join(root, "evil")
        misleading_clean_dir = os.path.join(root, "clean")
        neutral_dir = os.path.join(root, "uploads")
        os.makedirs(misleading_evil_dir)
        os.makedirs(misleading_clean_dir)
        os.makedirs(neutral_dir)

        cases = []
        for payload in payloads:
            for _ in range(4):
                width = 11 + secrets.randbelow(18)
                height = 11 + secrets.randbelow(18)
                color = tuple(secrets.randbelow(256) for _ in range(3))
                image = Image.new("RGB", (width, height), color=color)
                buffer = io.BytesIO()
                image.save(buffer, format="PNG")
                clean_bytes = buffer.getvalue()
                evil_bytes = clean_bytes + payload

                # Deliberately put benign content beneath an "evil" path and
                # malicious content beneath a "clean" path.
                clean_path = os.path.join(misleading_evil_dir, secrets.token_hex(12) + ".png")
                evil_path = os.path.join(misleading_clean_dir, secrets.token_hex(12) + ".png")
                with open(clean_path, "wb") as f:
                    f.write(clean_bytes)
                with open(evil_path, "wb") as f:
                    f.write(evil_bytes)
                cases.extend([(clean_path, 0), (evil_path, 1)])

                # Also exercise both labels under the same neutrally named directory.
                neutral_clean = os.path.join(neutral_dir, secrets.token_hex(12) + ".png")
                neutral_evil = os.path.join(neutral_dir, secrets.token_hex(12) + ".png")
                with open(neutral_clean, "wb") as f:
                    f.write(clean_bytes)
                with open(neutral_evil, "wb") as f:
                    f.write(evil_bytes)
                cases.extend([(neutral_clean, 0), (neutral_evil, 1)])

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            try:
                result = subprocess.run(
                    ["python3", script_path, path],
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue
            if result.returncode != expected:
                failures.append(
                    f"{path}: expected exit {expected}, got {result.returncode}"
                )

        assert not failures, "Dynamic content tests failed: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
