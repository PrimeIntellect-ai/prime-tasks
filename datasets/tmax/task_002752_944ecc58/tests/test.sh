#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import time


def run_filter(script_path, payload):
    fd, payload_path = tempfile.mkstemp(prefix="request_", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f, separators=(",", ":"))
        return subprocess.run(
            [script_path, payload_path], capture_output=True, timeout=15
        )
    finally:
        os.unlink(payload_path)


def video_frame_count(path="/app/test_video.mp4"):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames", "-of", "default=nw=1:nk=1", path,
        ],
        capture_output=True, text=True, check=True, timeout=30,
    )
    return int(result.stdout.strip())


def test_deployment_structure():
    v1_dir = "/home/user/deployment/releases/v1.0.0"
    v2_dir = "/home/user/deployment/releases/v2.0.0"
    current_link = "/home/user/deployment/current"

    assert os.path.isdir(v1_dir), f"Directory missing: {v1_dir}"
    assert os.path.isdir(v2_dir), f"Directory missing: {v2_dir}"
    assert os.path.islink(current_link), f"Not a symlink: {current_link}"

    target = os.readlink(current_link)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(current_link), target))

    assert target == v2_dir, f"Symlink {current_link} points to {target}, expected {v2_dir}"


def test_filter_script_corpus():
    script_path = "/home/user/deployment/current/filter.py"
    assert os.path.isfile(script_path), f"Filter script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Filter script is not executable: {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]

    failed_clean = []
    for path in clean_files:
        result = subprocess.run([script_path, path], capture_output=True, timeout=15)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(path))

    failed_evil = []
    for path in evil_files:
        result = subprocess.run([script_path, path], capture_output=True, timeout=15)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(path))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    assert not errors, " | ".join(errors)


def test_filter_generated_requests_and_actual_video_length():
    script_path = "/home/user/deployment/current/filter.py"
    total = video_frame_count()
    token = secrets.token_hex(10)

    valid_callbacks = [
        f"https://{token}.example/path_a-b?x={secrets.token_hex(5)}",
        f"http://a.example/{token}",
        f"ABCxyz0123456789:/.-_?={token}",
    ]
    valid_frames = {0, 1, total, random.randint(1, max(1, total))}
    for frame in valid_frames:
        for callback in valid_callbacks:
            result = run_filter(script_path, {"callback": callback, "frame": frame})
            assert result.returncode == 0, (
                f"Valid generated request rejected: frame={frame}, callback={callback!r}, "
                f"stderr={result.stderr.decode(errors='replace')}"
            )

    for excess in (1, random.randint(2, 50), random.randint(51, 500)):
        result = run_filter(script_path, {"frame": total + excess, "callback": valid_callbacks[0]})
        assert result.returncode != 0, f"Out-of-range frame {total + excess} was accepted"

    disallowed = [" ", ";", "$", "|", "&", "`", "!", "@", "#", "%", "^", "*", "+", ",", "(", ")", "[", "]", "{", "}", "\\", "'", "\"", "\t", "\n"]
    random.shuffle(disallowed)
    for bad in disallowed:
        callback = f"https://safe.example/{token}{bad}{secrets.token_hex(3)}"
        result = run_filter(script_path, {"frame": random.randint(0, total), "callback": callback})
        assert result.returncode != 0, f"Callback containing forbidden character {bad!r} was accepted"

    # Replace the source briefly with a video having an unpredictable frame count.
    # This catches filters that hard-code the frame count of the shipped corpus video.
    video = "/app/test_video.mp4"
    backup = os.path.join("/tmp", f"test_video_backup_{secrets.token_hex(8)}.mp4")
    requested_frames = random.randint(11, 29)
    os.replace(video, backup)
    try:
        subprocess.run(
            [
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=black:s=64x64:r=7", "-frames:v", str(requested_frames),
                "-c:v", "mpeg4", "-y", video,
            ],
            check=True, timeout=30,
        )
        os.chmod(video, 0o666)
        changed_total = video_frame_count(video)
        assert changed_total == requested_frames

        accepted = run_filter(script_path, {"frame": changed_total, "callback": f"https://{token}.example/ok"})
        rejected = run_filter(script_path, {"frame": changed_total + 1, "callback": f"https://{token}.example/ok"})
        assert accepted.returncode == 0, "Filter did not accept the last frame of the current source video"
        assert rejected.returncode != 0, "Filter did not derive the changed source video's frame count"
    finally:
        if os.path.exists(video):
            os.unlink(video)
        os.replace(backup, video)


def test_log_rotation():
    rotate_script = "/home/user/deployment/current/rotate.sh"
    assert os.path.isfile(rotate_script), f"Rotate script missing: {rotate_script}"
    assert os.access(rotate_script, os.X_OK), f"Rotate script is not executable: {rotate_script}"

    logs_dir = "/home/user/logs"
    access_log = os.path.join(logs_dir, "access.log")
    os.makedirs(logs_dir, exist_ok=True)

    # Start from a controlled archive set so every required rename can be observed.
    for path in glob.glob(os.path.join(logs_dir, "access.log.*")):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    markers = []
    for i in range(5):
        marker = f"log-entry-{i}-{secrets.token_hex(8)}\n"
        markers.append(marker)
        with open(access_log, "w") as f:
            f.write(marker)

        before = int(time.time())
        result = subprocess.run([rotate_script], capture_output=True, timeout=15)
        after = int(time.time())
        assert result.returncode == 0, (
            f"Rotate script failed on run {i + 1}: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(access_log), "New access.log was not created"
        assert os.path.getsize(access_log) == 0, "New access.log is not empty"

        archives = glob.glob(os.path.join(logs_dir, "access.log.*"))
        assert len(archives) == min(i + 1, 3), (
            f"Expected {min(i + 1, 3)} archived logs after run {i + 1}, found {len(archives)}"
        )
        assert len(archives) <= 3, f"Expected at most 3 archived logs, found {len(archives)}"

        matching = []
        for archive in archives:
            assert os.path.isfile(archive), f"Archive is not a file: {archive}"
            match = re.fullmatch(r"access\.log\.(\d+)", os.path.basename(archive))
            assert match, f"Archive does not use access.log.<Unix epoch> naming: {archive}"
            timestamp = int(match.group(1))
            assert before - 2 <= timestamp <= after + 2, f"Archive timestamp is not current: {archive}"
            with open(archive) as f:
                if f.read() == marker:
                    matching.append(archive)
        assert len(matching) == 1, "Current access.log was not renamed intact to one timestamped archive"
        time.sleep(1.1)

    archives = glob.glob(os.path.join(logs_dir, "access.log.*"))
    assert len(archives) <= 3, f"Expected at most 3 archived logs, found {len(archives)}"
    surviving_contents = set()
    for archive in archives:
        with open(archive) as f:
            surviving_contents.add(f.read())
    assert surviving_contents == set(markers[-3:]), "Rotation did not retain exactly the three newest archives"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
