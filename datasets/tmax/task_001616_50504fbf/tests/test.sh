#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import shlex
import shutil
import subprocess
import tempfile

import pytest

OUTPUT_FILE = "/home/user/archived_segment.mp4"
CAMERA_FEED = "/app/camera_feed.mp4"
REFERENCE_FILE = "/tmp/reference_segment.mp4"
CPP_FILE = "/home/user/archiver.cpp"
EXECUTABLE = "/tmp/archiver_under_test"
METADATA_DIR = "/app/backup_metadata"


def run_checked(cmd, message, timeout=180):
    try:
        return subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        details = getattr(exc, "stderr", "") or ""
        pytest.fail(f"{message}\n{details[-2000:]}")


def make_reference(start, end, path):
    run_checked([
        "ffmpeg", "-y", "-ss", str(start), "-t", str(end - start),
        "-i", CAMERA_FEED,
        "-vf", "format=gray,scale=iw/2:ih/2",
        "-c:v", "libx264", "-crf", "0", path,
    ], "Fail: Could not generate the reference segment using ffmpeg.")


def ssim_against(reference, output):
    result = subprocess.run([
        "ffmpeg", "-i", reference, "-i", output,
        "-lavfi", "ssim", "-f", "null", "-",
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    match = re.search(r"All:([0-9.]+)", result.stderr)
    assert match is not None, (
        "Fail: Could not parse SSIM score from ffmpeg output. "
        "Is the output file a valid video?"
    )
    return float(match.group(1))


def probe_output(path):
    result = run_checked([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height:format=duration",
        "-of", "default=noprint_wrappers=1", path,
    ], "Fail: Could not probe the generated output video.")
    values = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return int(values["width"]), int(values["height"]), float(values["duration"])


@pytest.fixture(scope="session", autouse=True)
def compile_and_exercise_program():
    assert os.path.isfile(CPP_FILE), f"Fail: {CPP_FILE} does not exist."

    try:
        opencv_flags = shlex.split(subprocess.check_output(
            ["pkg-config", "--cflags", "--libs", "opencv4"],
            text=True,
            stderr=subprocess.STDOUT,
        ))
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        pytest.fail(f"Fail: OpenCV development files are unavailable: {exc}")

    run_checked(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", EXECUTABLE] + opencv_flags,
        "Fail: archiver.cpp could not be compiled with OpenCV.",
    )

    backup_root = tempfile.mkdtemp(prefix="metadata_backup_")
    backup_dir = os.path.join(backup_root, "backup_metadata")
    shutil.copytree(METADATA_DIR, backup_dir)

    # Use a fresh, unpredictable Critical interval so a program hardcoding the
    # image's original 3..7 interval cannot pass.
    start = random.choice([0, 1, 5, 6])
    end = start + random.choice([2, 3])
    challenge_reference = "/tmp/challenge_reference.mp4"

    try:
        shutil.rmtree(METADATA_DIR)
        os.makedirs(METADATA_DIR)
        with open(os.path.join(METADATA_DIR, "verification.log"), "w") as f:
            f.write(
                "[Record Start]\n"
                "ID: 9001\n"
                "Priority: Low\n"
                "Start_Sec: 8\n"
                "End_Sec: 9\n"
                "[Record End]\n\n"
                "[Record Start]\n"
                "ID: 9002\n"
                "Priority: Critical\n"
                f"Start_Sec: {start}\n"
                f"End_Sec: {end}\n"
                "[Record End]\n"
            )

        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        run_checked([EXECUTABLE], "Fail: compiled archiver program did not run successfully.")
        assert os.path.isfile(OUTPUT_FILE), "Fail: archiver did not generate its output when executed."
        assert os.path.getsize(OUTPUT_FILE) <= 200000, "Fail: challenge output exceeds 200,000 bytes."

        width, height, duration = probe_output(OUTPUT_FILE)
        assert (width, height) == (960, 540), (
            f"Fail: output dimensions are {width}x{height}, expected 960x540."
        )
        assert abs(duration - (end - start)) <= 0.25, (
            f"Fail: output duration {duration:.3f}s does not match metadata interval "
            f"{start}..{end}."
        )

        make_reference(start, end, challenge_reference)
        score = ssim_against(challenge_reference, OUTPUT_FILE)
        assert score >= 0.85, (
            f"Fail: SSIM score {score} is below 0.85 for the metadata-derived interval."
        )
    finally:
        shutil.rmtree(METADATA_DIR, ignore_errors=True)
        shutil.copytree(backup_dir, METADATA_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        # Re-run against the original metadata so the required final artifact is
        # present for all original assertions.
        run_checked([EXECUTABLE], "Fail: archiver failed against the original metadata.")

    yield


def test_cpp_program_exists():
    """Check if the C++ program was created at the specified path."""
    assert os.path.isfile(CPP_FILE), f"Fail: {CPP_FILE} does not exist."


def test_output_file_exists():
    """Check if the archived segment video was generated."""
    assert os.path.isfile(OUTPUT_FILE), f"Fail: {OUTPUT_FILE} does not exist."


def test_file_size_constraint():
    """Check if the archived segment is heavily compressed (<= 200,000 bytes)."""
    size = os.path.getsize(OUTPUT_FILE)
    assert size <= 200000, f"Fail: File size {size} bytes exceeds 200,000 bytes."


def test_ssim_metric():
    """Generate a reference segment and compute the SSIM metric to ensure quality threshold."""
    cmd_ref = [
        "ffmpeg", "-y", "-ss", "3", "-t", "4", "-i", CAMERA_FEED,
        "-vf", "format=gray,scale=iw/2:ih/2", "-c:v", "libx264", "-crf", "0", REFERENCE_FILE
    ]
    try:
        subprocess.run(cmd_ref, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except subprocess.CalledProcessError:
        pytest.fail("Fail: Could not generate the reference segment using ffmpeg.")

    cmd_ssim = [
        "ffmpeg", "-i", REFERENCE_FILE, "-i", OUTPUT_FILE,
        "-lavfi", "ssim", "-f", "null", "-"
    ]
    result = subprocess.run(cmd_ssim, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    match = re.search(r'All:([0-9.]+)', result.stderr)
    assert match is not None, "Fail: Could not parse SSIM score from ffmpeg output. Is the output file a valid video?"

    ssim_score = float(match.group(1))
    assert ssim_score >= 0.85, f"Fail: SSIM score {ssim_score} is below the threshold of 0.85."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
