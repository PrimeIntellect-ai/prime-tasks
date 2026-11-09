#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import uuid

import pytest


def test_exploit_frame_extraction():
    frame_file = "/home/user/exploit_frame.txt"
    assert os.path.exists(frame_file), f"Expected output file missing at {frame_file}"

    with open(frame_file, "r") as f:
        content = f.read().strip()

    try:
        frame_num = int(content)
    except ValueError:
        pytest.fail(f"Content of {frame_file} is not a valid integer: '{content}'")

    assert 140 <= frame_num <= 144, f"Frame number {frame_num} is outside the acceptable range (140-144). Expected ~142."

    video = "/app/sandbox_review.mp4"
    assert os.path.isfile(video), f"Video missing at {video}"

    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-an", "-f", "framemd5", "-"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not inspect video: {result.stderr}"

    hashes = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            fields = [field.strip() for field in line.split(",")]
            if len(fields) >= 6:
                hashes.append(fields[-1])

    assert hashes, "ffmpeg produced no frame hashes"
    expected_frame = next((i for i, digest in enumerate(hashes) if digest != hashes[0]), None)
    assert expected_frame is not None, "No visual transition was found in the video"

    def ocr_frame(index):
        image = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-i", video,
                "-vf", f"select=eq(n\\,{index}),crop=iw:100:0:0,scale=iw*2:ih*2",
                "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-",
            ],
            capture_output=True,
            timeout=30,
        )
        assert image.returncode == 0 and image.stdout, f"Could not extract frame {index}"
        ocr = subprocess.run(
            ["tesseract", "stdin", "stdout", "--psm", "6"],
            input=image.stdout,
            capture_output=True,
            timeout=30,
        )
        assert ocr.returncode == 0, f"OCR failed for frame {index}"
        return re.sub(r"[^A-Z0-9]", "", ocr.stdout.decode(errors="replace").upper())

    assert "EXPLOITSUCCESS" in ocr_frame(expected_frame), (
        f"The first changed frame ({expected_frame}) does not contain EXPLOIT_SUCCESS"
    )
    if expected_frame > 0:
        assert "EXPLOITSUCCESS" not in ocr_frame(expected_frame - 1), (
            "EXPLOIT_SUCCESS was already visible in the preceding frame"
        )

    assert frame_num == expected_frame, (
        f"Frame number {frame_num} is not the exact first visible frame {expected_frame}"
    )


def run_detector(detector_script, path):
    try:
        return subprocess.run(
            ["python3", detector_script, path],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {os.path.basename(path)}")


def test_detector_adversarial_corpus():
    detector_script = "/home/user/detector.py"
    assert os.path.exists(detector_script), f"Detector script missing at {detector_script}"
    assert os.path.isfile(detector_script), f"Detector is not a regular file: {detector_script}"

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.exists(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert evil_files, "No evil files found to test against."
    assert clean_files, "No clean files found to test against."

    evil_bypassed = []
    for fpath in evil_files:
        if run_detector(detector_script, fpath) != 1:
            evil_bypassed.append(os.path.basename(fpath))

    clean_modified = []
    for fpath in clean_files:
        if run_detector(detector_script, fpath) != 0:
            clean_modified.append(os.path.basename(fpath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (false positives): {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_detector_generated_hidden_cases():
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Detector script missing at {detector_script}"

    token = secrets.token_hex(8)
    evil_contents = [
        f"ordinary log prefix SBX_SECRET_{token} ordinary suffix\n",
        f"SBX_SECRET_{secrets.token_hex(8)}\n",
        "payload bytes: 7f 45 4c 46 02 01 01 00\n",
        "payload bytes: 7F454C46AABBCCDD\n",
        "payload bytes: 7f   45 4C  46 00\n",
    ]
    clean_contents = [
        "standard application log: request completed\n",
        "Log entry: SBX_SECRET_REDACTED\n",
        "short value: SBX_SECRET_0123456789abcde\n",
        "long value: SBX_SECRET_0123456789abcdef0\n",
        "uppercase value: SBX_SECRET_ABCDEF0123456789\n",
        "non-ELF bytes: 7f 45 4c 47\n",
        "interrupted bytes: 7f 45 xx 4c 46\n",
        "PNG dump: 89504e470d0a1a0a\n",
    ]

    cases = [(1, text) for text in evil_contents] + [(0, text) for text in clean_contents]
    secrets.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sandbox-check-") as directory:
        failures = []
        for expected, text in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".txt")
            with open(path, "w") as f:
                f.write(text)
            actual = run_detector(detector_script, path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")

        assert not failures, "Generated detector cases failed: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
