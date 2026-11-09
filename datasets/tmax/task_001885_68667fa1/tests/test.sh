#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/detect_slip.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VIDEO_PATH = "/app/backup_cam.mp4"
RED_FRAME_COUNT_FILE = "/home/user/red_frame_count.txt"
EXPECTED_RED_FRAMES = 34


def run_detector(manifest):
    return subprocess.run(
        [SCRIPT_PATH, str(manifest)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def path_is_evil(value):
    if value.startswith("/"):
        return True
    depth = 0
    for component in value.split("/"):
        if component in ("", "."):
            continue
        if component == "..":
            if depth == 0:
                return True
            depth -= 1
        else:
            depth += 1
    return False


def random_component():
    return "p_" + secrets.token_hex(6)


def make_random_path(want_evil):
    a, b, c, d = [random_component() for _ in range(4)]
    if want_evil:
        choices = [
            f"../{a}",
            f"{a}/../../{b}",
            f"/{a}/{b}",
            f"./../../{a}/{b}",
            f"{a}/{b}/../../../{c}",
            f"{a}/../..//{d}",
        ]
    else:
        choices = [
            a,
            f"{a}/{b}",
            f"./{a}/{b}",
            f"{a}//{b}/./{c}",
            f"{a}/../{b}/{c}",
            f"{a}/{b}/../../{c}/{d}",
            f"{a}/./{b}/../{c}",
        ]
    value = random.SystemRandom().choice(choices)
    assert path_is_evil(value) == want_evil
    return value


def write_manifest(path, paths):
    records = []
    for file_path in paths:
        records.append(
            "[RECORD]\n"
            f"ID: {secrets.randbelow(900000) + 100000}\n"
            f"File-Path: {file_path}\n"
            f"Size: {secrets.randbelow(1000000)}\n"
            "[END]"
        )
    path.write_text("\n\n".join(records) + "\n", encoding="utf-8")


def independently_count_red_frames(video_path):
    probe = subprocess.run(
        [
            "/usr/bin/ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
            video_path,
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=20,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    frame_size = width * height * 3

    proc = subprocess.Popen(
        [
            "/usr/bin/ffmpeg", "-v", "error", "-i", video_path,
            "-map", "0:v:0", "-vsync", "0", "-f", "rawvideo",
            "-pix_fmt", "rgb24", "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    count = 0
    frames = 0
    while True:
        data = proc.stdout.read(frame_size)
        if not data:
            break
        assert len(data) == frame_size, "ffmpeg produced a partial video frame"
        frames += 1
        pixels = width * height
        mean_r = sum(data[0::3]) / pixels
        mean_g = sum(data[1::3]) / pixels
        mean_b = sum(data[2::3]) / pixels
        if mean_r >= 200 and mean_g <= 40 and mean_b <= 40:
            count += 1

    stderr = proc.stderr.read().decode("utf-8", errors="replace")
    assert proc.wait(timeout=20) == 0, stderr
    assert frames > 0, "No frames could be decoded from the video"
    return count


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.manifest"))
    assert clean_files, f"No clean manifests found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for manifest in clean_files:
        result = run_detector(manifest)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            failed_files.append(os.path.basename(manifest))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean manifests incorrectly flagged as EVIL or failed: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.manifest"))
    assert evil_files, f"No evil manifests found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for manifest in evil_files:
        result = run_detector(manifest)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "EVIL":
            failed_files.append(os.path.basename(manifest))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil manifests bypassed detection: {', '.join(failed_files)}")


def test_randomized_unlabelled_manifests():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="manifest_checks_") as directory:
        directory = Path(directory)
        cases = []

        for expected_evil in ([False] * 24 + [True] * 24):
            record_count = rng.randint(1, 5)
            if expected_evil:
                paths = [make_random_path(False) for _ in range(record_count - 1)]
                paths.append(make_random_path(True))
                rng.shuffle(paths)
            else:
                paths = [make_random_path(False) for _ in range(record_count)]

            expected_evil = any(path_is_evil(value) for value in paths)
            manifest = directory / (secrets.token_hex(12) + ".manifest")
            write_manifest(manifest, paths)
            cases.append((manifest, expected_evil))

        rng.shuffle(cases)
        failures = []
        for manifest, expected_evil in cases:
            result = run_detector(manifest)
            expected_code = 1 if expected_evil else 0
            expected_output = "EVIL" if expected_evil else "CLEAN"
            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                failures.append(manifest.name)

        assert not failures, f"Detector failed {len(failures)} randomized manifests"


def test_red_frame_count():
    assert os.path.isfile(RED_FRAME_COUNT_FILE), f"Output file not found at {RED_FRAME_COUNT_FILE}"
    with open(RED_FRAME_COUNT_FILE, "r") as f:
        content = f.read().strip()

    try:
        count = int(content)
    except ValueError:
        pytest.fail(f"File {RED_FRAME_COUNT_FILE} contains non-integer value: {content}")

    assert count == EXPECTED_RED_FRAMES, f"Expected {EXPECTED_RED_FRAMES} red frames, but got {count}"
    derived_count = independently_count_red_frames(VIDEO_PATH)
    assert count == derived_count, (
        f"Submitted count {count} does not match the {derived_count} red frames "
        "independently measured from the video"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
