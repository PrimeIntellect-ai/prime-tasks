#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import subprocess

import pytest

ARCHIVE_DIR = "/home/user/archive"
ORIGINAL_VIDEO = "/app/surveillance.mp4"
RECONSTRUCTED = "/tmp/reconstructed.mp4"
LOG_FILE = "/home/user/dedup_log.json"
SCRIPT_FILE = "/home/user/process_footage.py"
EXPECTED_NAMES = [f"chunk_{i:02d}.mp4" for i in range(60)]


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def probe_video(path):
    result = run([
        "ffprobe", "-v", "error", "-count_frames",
        "-select_streams", "v:0",
        "-show_entries", "stream=nb_read_frames,duration:format=duration",
        "-of", "json", path,
    ], text=True)
    assert result.returncode == 0, f"ffprobe failed for {path}: {result.stderr}"
    data = json.loads(result.stdout)
    assert data.get("streams"), f"No video stream in {path}"
    stream = data["streams"][0]
    duration = float(data.get("format", {}).get("duration") or stream.get("duration"))
    frames = int(stream["nb_read_frames"])
    return duration, frames


def derive_motion_from_original():
    """Derive per-second motion labels from decoded frames of the supplied video."""
    width, height = 160, 120
    frame_size = width * height
    result = run([
        "ffmpeg", "-v", "error", "-i", ORIGINAL_VIDEO,
        "-map", "0:v:0", "-vf", f"scale={width}:{height},format=gray",
        "-vsync", "0", "-f", "rawvideo", "-pix_fmt", "gray", "-",
    ])
    assert result.returncode == 0, f"Could not decode original video: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == 60 * 30 * frame_size, (
        f"Original must decode to exactly 1800 frames; got {len(result.stdout) / frame_size:.2f}"
    )

    labels = {}
    raw = result.stdout
    for second in range(60):
        frames = []
        for frame_no in range(second * 30, (second + 1) * 30):
            start = frame_no * frame_size
            frames.append(raw[start:start + frame_size])

        motion = False
        for previous, current in zip(frames, frames[1:]):
            changed = sum(1 for a, b in zip(previous, current) if abs(a - b) > 2)
            if changed > 100:
                motion = True
                break
        labels[f"chunk_{second:02d}.mp4"] = motion

    # This also detects replacement or corruption of the supplied source video.
    known_motion = set(range(12, 19)) | set(range(35, 43)) | set(range(50, 56))
    derived_motion = {i for i in range(60) if labels[f"chunk_{i:02d}.mp4"]}
    assert derived_motion == known_motion, (
        f"Unexpected motion pattern in source video: {sorted(derived_motion)}"
    )
    return labels


def test_00_execute_processing_script():
    assert os.path.exists(SCRIPT_FILE), f"Missing required script: {SCRIPT_FILE}"
    assert os.path.isfile(SCRIPT_FILE), f"Script is not a regular file: {SCRIPT_FILE}"
    assert not os.path.islink(SCRIPT_FILE), "Processing script must not be a symlink"
    assert os.path.getsize(SCRIPT_FILE) > 0, "Processing script is empty"

    compile_result = run(["python3", "-m", "py_compile", SCRIPT_FILE], text=True)
    assert compile_result.returncode == 0, f"Processing script is not valid Python: {compile_result.stderr}"

    shutil.rmtree(ARCHIVE_DIR, ignore_errors=True)
    os.makedirs(ARCHIVE_DIR)
    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)
    if os.path.lexists(RECONSTRUCTED):
        os.unlink(RECONSTRUCTED)

    try:
        result = run(["python3", SCRIPT_FILE], text=True, timeout=180)
    except subprocess.TimeoutExpired:
        pytest.fail("Processing script did not finish within 180 seconds")
    assert result.returncode == 0, (
        f"Processing script exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_archive_directory_and_chunks():
    """Verify that the archive directory exists and contains 60 chunks."""
    assert os.path.exists(ARCHIVE_DIR), f"Archive directory not found: {ARCHIVE_DIR}"
    assert os.path.isdir(ARCHIVE_DIR), f"Archive path is not a directory: {ARCHIVE_DIR}"

    chunks = sorted([f for f in os.listdir(ARCHIVE_DIR) if f.endswith('.mp4')])
    assert len(chunks) == 60, f"Expected 60 chunks in archive, found {len(chunks)}"

    for i in range(60):
        expected_name = f"chunk_{i:02d}.mp4"
        assert expected_name in chunks, f"Missing expected chunk: {expected_name}"

    for name in EXPECTED_NAMES:
        path = os.path.join(ARCHIVE_DIR, name)
        assert not os.path.islink(path), f"Chunk must not be a symbolic link: {name}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Chunk is not a regular file: {name}"
        duration, frames = probe_video(path)
        assert frames == 30, f"{name} has {frames} frames instead of 30"
        assert 0.90 <= duration <= 1.10, f"{name} duration is {duration:.4f}s instead of 1 second"


def test_log_file():
    """Verify that the deduplication log exists, is valid JSON, and is correct."""
    assert os.path.exists(LOG_FILE), f"Log file not found: {LOG_FILE}"
    assert os.path.isfile(LOG_FILE), f"Log path is not a file: {LOG_FILE}"

    try:
        with open(LOG_FILE, 'r') as f:
            log_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Log file {LOG_FILE} is not valid JSON")

    assert isinstance(log_data, dict), "Log data must be a JSON dictionary"
    assert len(log_data) == 60, f"Expected 60 entries in log, found {len(log_data)}"
    assert set(log_data) == set(EXPECTED_NAMES), "Log keys must be exactly the 60 chunk filenames"
    assert all(type(value) is bool for value in log_data.values()), "Every log value must be a boolean"

    expected = derive_motion_from_original()
    assert log_data == expected, "Motion/static classifications in dedup_log.json are incorrect"


def test_hard_link_layout():
    """Static chunks must share the first static inode; motion chunks must be independent."""
    expected = derive_motion_from_original()
    static_names = [name for name in EXPECTED_NAMES if not expected[name]]
    motion_names = [name for name in EXPECTED_NAMES if expected[name]]
    assert static_names, "Source unexpectedly contains no static chunks"

    inode = lambda name: (os.stat(os.path.join(ARCHIVE_DIR, name)).st_dev,
                          os.stat(os.path.join(ARCHIVE_DIR, name)).st_ino)
    first_static_inode = inode(static_names[0])
    for name in static_names:
        assert inode(name) == first_static_inode, (
            f"Static chunk {name} is not hard-linked to {static_names[0]}"
        )

    static_stat = os.stat(os.path.join(ARCHIVE_DIR, static_names[0]))
    assert static_stat.st_nlink == len(static_names), (
        f"Static inode has {static_stat.st_nlink} links; expected {len(static_names)}"
    )

    motion_inodes = [inode(name) for name in motion_names]
    assert len(set(motion_inodes)) == len(motion_inodes), "Motion chunks are hard-linked to each other"
    assert first_static_inode not in motion_inodes, "A motion chunk is hard-linked to the static inode"
    for name in motion_names:
        assert os.stat(os.path.join(ARCHIVE_DIR, name)).st_nlink == 1, (
            f"Motion chunk {name} is not an independent file"
        )


def test_deduplication_score():
    """Verify the fidelity (PSNR) and storage savings metric."""
    assert os.path.exists(ARCHIVE_DIR), f"Archive directory not found: {ARCHIVE_DIR}"

    chunks = sorted([f for f in os.listdir(ARCHIVE_DIR) if f.endswith('.mp4')])
    assert len(chunks) == 60, f"Expected 60 chunks in archive, found {len(chunks)}"

    concat_txt = "/tmp/concat.txt"
    with open(concat_txt, "w") as f:
        for chunk in chunks:
            f.write(f"file '{os.path.join(ARCHIVE_DIR, chunk)}'\n")

    concat_cmd = [
        "ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", concat_txt, "-c", "copy", RECONSTRUCTED
    ]
    concat_result = subprocess.run(concat_cmd, capture_output=True, text=True, check=False)
    assert concat_result.returncode == 0, f"Failed to reconstruct video: {concat_result.stderr}"
    assert os.path.exists(RECONSTRUCTED), "Failed to reconstruct video from chunks"

    reconstructed_duration, reconstructed_frames = probe_video(RECONSTRUCTED)
    assert reconstructed_frames == 1800, f"Reconstruction has {reconstructed_frames} frames instead of 1800"
    assert 59.5 <= reconstructed_duration <= 60.5, (
        f"Reconstruction duration is {reconstructed_duration:.3f}s instead of 60 seconds"
    )

    psnr_cmd = [
        "ffmpeg", "-i", ORIGINAL_VIDEO, "-i", RECONSTRUCTED,
        "-lavfi", "psnr", "-f", "null", "-"
    ]
    result = subprocess.run(psnr_cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"PSNR comparison failed: {result.stderr}"
    psnr_output = result.stderr

    psnr_val = 0.0
    match = re.search(r'average:([0-9.]+)', psnr_output)
    if match:
        psnr_val = float(match.group(1))
    elif 'average:inf' in psnr_output:
        psnr_val = 100.0
    else:
        pytest.fail(f"Could not parse PSNR from ffmpeg output: {psnr_output}")

    du_cmd = ["du", "-sb", ARCHIVE_DIR]
    du_result = subprocess.run(du_cmd, capture_output=True, text=True)
    try:
        size_bytes = int(du_result.stdout.split()[0])
    except (IndexError, ValueError):
        pytest.fail(f"Could not parse directory size from du output: {du_result.stdout}")

    size_mb = size_bytes / (1024 * 1024)
    expected_uncompressed_mb = 12.0
    ratio = min(size_mb / expected_uncompressed_mb, 1.0)
    score = psnr_val * (1.0 - ratio)

    assert score >= 20.0, (
        f"Metric threshold failed: Score {score:.2f} < 20.0. "
        f"PSNR: {psnr_val:.2f}, Size: {size_mb:.2f} MB"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
