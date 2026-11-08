#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

BINARY_PATH = "/home/user/video_analyzer/target/release/payload_filter"
VIDEO_PATH = "/app/video_fixture.mp4"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"


def frame_count(path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames", "-of", "default=nw=1:nk=1", path,
        ],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    return int(result.stdout.strip())


def run_filter(args, cwd):
    try:
        result = subprocess.run(
            [BINARY_PATH, *args],
            capture_output=True,
            text=True,
            timeout=5,
            cwd=cwd,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"payload_filter timed out for arguments: {args}")

    assert result.returncode >= 0, f"payload_filter was terminated by a signal for arguments: {args}"
    stderr = result.stderr.lower()
    assert "panicked at" not in stderr and "thread 'main' panicked" not in stderr, \
        f"payload_filter panicked for arguments: {args}\n{result.stderr}"
    assert not any(name.startswith("core") for name in os.listdir(cwd)), \
        f"payload_filter produced a core dump for arguments: {args}"
    return result


def write_payload(directory, payload):
    path = os.path.join(directory, secrets.token_hex(12) + ".json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    return path


def assert_accepted(path, cwd):
    result = run_filter([path], cwd)
    assert result.returncode == 0, f"valid payload was rejected: {path}"


def assert_rejected(args, cwd):
    result = run_filter(args, cwd)
    assert result.returncode != 0, f"invalid invocation was accepted: {args}"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Expected binary not found at {BINARY_PATH}. Did you compile it in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"The file at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "payload_filter must be a compiled standalone binary, not a script."


def test_payload_filter_behavior():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".json")]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".json")]
    assert evil_files, "No JSON files found in evil corpus."
    assert clean_files, "No JSON files found in clean corpus."

    with tempfile.TemporaryDirectory(prefix="payload_filter_test_") as work:
        # Preserve the original corpus assertions.
        evil_bypassed = []
        clean_modified = []
        for path in evil_files:
            try:
                if run_filter([path], work).returncode == 0:
                    evil_bypassed.append(os.path.basename(path))
            except AssertionError as exc:
                evil_bypassed.append(f"{os.path.basename(path)} ({exc})")
        for path in clean_files:
            try:
                if run_filter([path], work).returncode != 0:
                    clean_modified.append(os.path.basename(path))
            except AssertionError as exc:
                clean_modified.append(f"{os.path.basename(path)} ({exc})")
        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean rejected: {', '.join(clean_modified)}")
        assert not errors, " | ".join(errors)

        # Exercise randomized payload paths and values against the actual video size.
        count = frame_count(VIDEO_PATH)
        assert count > 1, "Video fixture has no usable frames."
        valid = write_payload(work, {
            "frame_index": random.SystemRandom().randrange(count),
            "motion_vectors": [secrets.randbelow(10000) / 997.0 + 0.01 for _ in range(3)],
        })
        assert_accepted(valid, work)

        assert_rejected([], work)
        assert_rejected([valid, valid], work)
        assert_rejected([write_payload(work, {"frame_index": count, "motion_vectors": [1.25, 2.5]})], work)
        assert_rejected([write_payload(work, {"frame_index": count + secrets.randbelow(1000) + 1, "motion_vectors": [3.5]})], work)
        assert_rejected([write_payload(work, {"frame_index": random.SystemRandom().randrange(count), "motion_vectors": [1.0, -0.5, 2.0]})], work)
        assert_rejected([write_payload(work, {"frame_index": -1, "motion_vectors": [1.0]})], work)
        assert_rejected([os.path.join(work, secrets.token_hex(10) + ".json")], work)

        malformed = os.path.join(work, secrets.token_hex(12) + ".json")
        with open(malformed, "w", encoding="utf-8") as handle:
            handle.write('{"frame_index":4,"motion_vectors":[1.0,2.0]')
        assert_rejected([malformed], work)

        # Replace the fixture temporarily with a video having a runtime-randomized
        # frame count. This rejects implementations that hard-code the original 150.
        alternate_count = random.SystemRandom().randrange(31, 79)
        while alternate_count == count:
            alternate_count = random.SystemRandom().randrange(31, 79)
        backup = os.path.join(work, "video_fixture.backup.mp4")
        alternate = os.path.join(work, "video_fixture.alternate.mp4")
        shutil.copy2(VIDEO_PATH, backup)
        subprocess.run(
            [
                "ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                "color=c=black:s=160x120:r=30", "-frames:v", str(alternate_count),
                "-c:v", "libx264", "-preset", "ultrafast", alternate,
            ],
            timeout=30,
            check=True,
        )
        assert frame_count(alternate) == alternate_count
        try:
            os.replace(alternate, VIDEO_PATH)
            dynamic_valid = write_payload(work, {
                "frame_index": alternate_count - 1,
                "motion_vectors": [0.25, 1.75, 4.5],
            })
            dynamic_invalid = write_payload(work, {
                "frame_index": alternate_count,
                "motion_vectors": [0.25, 1.75, 4.5],
            })
            assert_accepted(dynamic_valid, work)
            assert_rejected([dynamic_invalid], work)
        finally:
            os.replace(backup, VIDEO_PATH)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
