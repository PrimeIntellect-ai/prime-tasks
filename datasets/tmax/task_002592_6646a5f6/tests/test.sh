#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import string
import subprocess
import tempfile
import uuid

import pytest

SANITIZER = "/home/user/sanitizer.py"


def run_sanitizer(filepath):
    return subprocess.run(
        ["python3", SANITIZER, filepath],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=15,
    ).returncode


def test_corrupted_frame_txt():
    path = "/home/user/corrupted_frame.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "74", f"Expected corrupted_frame.txt to contain '74', but found '{content}'"


def test_sanitizer_exists():
    path = SANITIZER
    assert os.path.isfile(path), f"Missing required script: {path}"


def test_sanitizer_evil_corpus():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.mp4"))

    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    bypassed_files = []
    for filepath in evil_files:
        if run_sanitizer(filepath) != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the sanitizer (expected exit code 1). "
            f"Offending files: {', '.join(bypassed_files)}"
        )


def test_sanitizer_clean_corpus():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.mp4"))

    assert len(clean_files) > 0, f"No files found in {clean_dir}"

    modified_files = []
    for filepath in clean_files:
        if run_sanitizer(filepath) != 0:
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        pytest.fail(
            f"{len(modified_files)} of {len(clean_files)} clean files were incorrectly rejected (expected exit code 0). "
            f"Offending files: {', '.join(modified_files)}"
        )


def test_sanitizer_randomized_metadata_cases():
    with tempfile.TemporaryDirectory(prefix="video_checks_") as workdir:
        base = os.path.join(workdir, "base.mp4")
        subprocess.run(
            [
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=gray:s=96x96:r=5:d=0.4",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", base,
            ],
            check=True,
            timeout=30,
        )

        alphabet = string.ascii_letters + string.digits
        cases = [("-2147483648", 1) for _ in range(6)]
        cases += [
            ("".join(secrets.choice(alphabet) for _ in range(11)), 0)
            for _ in range(6)
        ]
        secrets.SystemRandom().shuffle(cases)

        generated = []
        for comment, expected in cases:
            path = os.path.join(workdir, f"{uuid.uuid4().hex}.mp4")
            subprocess.run(
                [
                    "ffmpeg", "-v", "error", "-i", base, "-map", "0",
                    "-c", "copy", "-metadata", f"comment={comment}", "-y", path,
                ],
                check=True,
                timeout=30,
            )
            generated.append((path, expected))

        failures = []
        for path, expected in generated:
            actual = run_sanitizer(path)
            if actual != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected exit {expected}, got {actual}"
                )

        if failures:
            pytest.fail("Randomized metadata classification failed: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
