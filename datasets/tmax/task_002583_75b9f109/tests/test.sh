#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import tempfile

from PIL import Image, ImageOps
import pytesseract

FILTER_SCRIPT = "/home/user/job_filter.py"


def run_filter(value):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, value],
        capture_output=True,
        text=True,
        timeout=5,
    )


def extract_failed_jobs_from_video():
    video = "/app/incident_monitor.mp4"
    assert os.path.isfile(video), f"{video} does not exist."

    with tempfile.TemporaryDirectory() as frame_dir:
        result = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", video, "-vsync", "0", os.path.join(frame_dir, "frame_%04d.png")
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"ffmpeg could not decode the incident video: {result.stderr}"

        jobs = set()
        for name in sorted(os.listdir(frame_dir)):
            path = os.path.join(frame_dir, name)
            with Image.open(path) as source:
                image = source.convert("RGB")

            pixels = list(image.getdata())
            red_fraction = sum(r > 150 and g < 110 and b < 110 for r, g, b in pixels) / len(pixels)
            if red_fraction < 0.50:
                continue

            # Isolate the white dashboard lettering from the solid red failure frame.
            mask = Image.new("L", image.size, 255)
            mask.putdata([
                0 if r > 150 and g > 150 and b > 150 else 255
                for r, g, b in pixels
            ])
            bbox = ImageOps.invert(mask).getbbox()
            assert bbox is not None, f"No failure text found in red frame {name}"
            text_image = mask.crop(bbox)
            text_image = ImageOps.expand(text_image, border=20, fill=255)
            text_image = text_image.resize(
                (text_image.width * 8, text_image.height * 8),
                Image.Resampling.NEAREST,
            )
            text = pytesseract.image_to_string(text_image, config="--psm 7")
            match = re.search(r"FAILURE\s*:\s*JOB[_\s-]*(\d+)", text, re.IGNORECASE)
            assert match, f"Could not read the failure label in {name}; OCR returned {text!r}"
            jobs.add(match.group(1))

    return sorted(jobs, key=int)


def test_trace_environment_scripts_exist():
    for job_id in range(1000, 1101):
        trace_dir = f"/app/traces/job_{job_id}"
        assert os.path.isdir(trace_dir), f"{trace_dir} does not exist."
        assert os.path.isfile(os.path.join(trace_dir, "strace.log"))
        assert os.path.isfile(os.path.join(trace_dir, "setup.sh")), (
            f"Missing promised environment setup script for job {job_id}"
        )


def test_failed_jobs_txt():
    expected_jobs = ["1012", "1045", "1099"]
    target_file = "/home/user/failed_jobs.txt"

    assert os.path.exists(target_file), f"{target_file} does not exist."

    with open(target_file, "r") as f:
        content = f.read().strip().splitlines()

    # Preserve the original assertion and independently derive the same answer
    # by decoding and reading the incident recording.
    assert content == expected_jobs, f"Expected {expected_jobs} in {target_file}, but got {content}."
    video_jobs = extract_failed_jobs_from_video()
    assert video_jobs == expected_jobs, f"Unexpected failure labels decoded from video: {video_jobs}"
    assert content == video_jobs, f"{target_file} does not match the incident recording."


def test_job_filter_script_on_original_corpora():
    assert os.path.isfile(FILTER_SCRIPT), f"{FILTER_SCRIPT} does not exist or is not a regular file."

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    assert os.path.isdir(evil_dir), f"{evil_dir} does not exist."
    assert os.path.isdir(clean_dir), f"{clean_dir} does not exist."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        with open(evil_file, "r") as f:
            test_input = f.read()
        result = run_filter(test_input)
        output = result.stdout.strip()
        if output != "REJECT" or result.returncode != 1:
            evil_bypassed.append((os.path.basename(evil_file), output, result.returncode))

    for clean_file in clean_files:
        with open(clean_file, "r") as f:
            test_input = f.read()
        result = run_filter(test_input)
        output = result.stdout.strip()
        if output != "ACCEPT" or result.returncode != 0:
            clean_modified.append((os.path.basename(clean_file), output, result.returncode))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {[f[0] for f in evil_bypassed]}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {[f[0] for f in clean_modified]}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msgs)


def test_job_filter_generalizes_beyond_visible_corpora():
    assert os.path.isfile(FILTER_SCRIPT), f"{FILTER_SCRIPT} does not exist or is not a regular file."

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_.-"
    safe_paths = []
    for _ in range(80):
        depth = rng.randint(1, 4)
        parts = []
        for _ in range(depth):
            length = rng.randint(3, 18)
            part = "".join(rng.choice(alphabet) for _ in range(length))
            parts.append(part)
        path = "/".join(parts) + rng.choice([".mp4", ".mov", ".mkv", ".avi"])
        if rng.choice([True, False]):
            path = "/mnt/uploads/" + path
        safe_paths.append(path)

    dangerous_tokens = [
        " ", "\t", "\n", ";", "'", "\"", "$(id)", "`id`", "&", "|",
        ">", "<", "(", ")", "*", "?", "[x]", "{x}", "\\", "!"
    ]
    evil_paths = []
    for _ in range(120):
        base = rng.choice(safe_paths)
        token = rng.choice(dangerous_tokens)
        position = rng.randrange(len(base) + 1)
        evil_paths.append(base[:position] + token + base[position:])

    failures = []
    for value in safe_paths:
        result = run_filter(value)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            failures.append(("safe", repr(value), result.stdout, result.returncode))

    for value in evil_paths:
        result = run_filter(value)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            failures.append(("evil", repr(value), result.stdout, result.returncode))

    assert not failures, f"Classifier failed generated cases: {failures[:10]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
