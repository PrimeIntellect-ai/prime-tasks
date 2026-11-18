#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import string
import subprocess

import pytest
from PIL import Image, ImageDraw

REPORT_PATH = "/home/user/drift_report.json"
LOGS_PATH = "/app/agent_logs.jsonl"
VIDEO_PATH = "/app/config_dashboard.mp4"
FRAMES_DIR = "/tmp/verifier_frames"


def get_commits_and_true_drifts():
    commits = []
    with open(LOGS_PATH, "r") as f:
        for line in f:
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue
            if data.get("event_type") == "config_commit":
                commits.append(data)

    commits.sort(key=lambda x: x["timestamp"])

    def normalize(payload):
        payload = payload.lower()
        to_remove = string.punctuation.replace("_", "")
        table = str.maketrans("", "", to_remove)
        return set(payload.translate(table).split())

    drifts = []
    prev_tokens = None
    for i, commit in enumerate(commits):
        tokens = normalize(commit["config_payload"])
        if i == 0:
            drift = 0.0
        else:
            intersection = len(tokens.intersection(prev_tokens))
            union = len(tokens.union(prev_tokens))
            jaccard = intersection / union if union > 0 else 1.0
            drift = 1.0 - jaccard
        drifts.append(drift)
        prev_tokens = tokens

    return commits, drifts


def extract_video_frames():
    os.makedirs(FRAMES_DIR, exist_ok=True)
    for name in os.listdir(FRAMES_DIR):
        os.unlink(os.path.join(FRAMES_DIR, name))

    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", VIDEO_PATH,
            "-vsync", "0", os.path.join(FRAMES_DIR, "frame_%04d.png")
        ],
        check=True,
    )
    return sorted(
        os.path.join(FRAMES_DIR, name)
        for name in os.listdir(FRAMES_DIR)
        if name.endswith(".png")
    )


def foreground_mask(image, threshold):
    gray = image.convert("L")
    return tuple(value > threshold for value in gray.getdata())


def rendered_line_matches(frame, timestamp, hash_value):
    template = Image.new("RGB", frame.size, color=(0, 0, 0))
    draw = ImageDraw.Draw(template)
    draw.text(
        (50, 200),
        f"TS: {timestamp} | HASH: {hash_value}",
        fill=(255, 255, 255),
    )

    # Compare the binary text image. Trying a small range of thresholds makes
    # this insensitive to minor H.264 luma shifts while retaining exact glyph
    # comparison for every hash character.
    crop_box = (35, 180, 400, 235)
    actual = frame.crop(crop_box)
    expected = foreground_mask(template.crop(crop_box), 128)
    best_mismatch = None
    for threshold in range(96, 177, 8):
        observed = foreground_mask(actual, threshold)
        mismatch = sum(a != b for a, b in zip(observed, expected))
        best_mismatch = mismatch if best_mismatch is None else min(best_mismatch, mismatch)
    return best_mismatch <= 2


def frame_is_black(frame):
    crop = frame.crop((35, 180, 400, 235)).convert("L")
    return max(crop.getdata()) < 32


def test_drift_report_mse_and_required_video_fields():
    assert os.path.exists(REPORT_PATH), f"Agent report missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Agent report at {REPORT_PATH} is not valid JSON.")

    assert isinstance(agent_data, list), "Agent report must be a JSON list."

    commits, true_drifts = get_commits_and_true_drifts()
    assert len(agent_data) == len(true_drifts), (
        f"Expected {len(true_drifts)} entries in report, but got {len(agent_data)}."
    )

    frames = extract_video_frames()
    assert len(frames) == len(commits), (
        f"Expected {len(commits)} video frames, but extracted {len(frames)}."
    )

    mse = 0.0
    for i, (agent_entry, commit, true_drift, frame_path) in enumerate(
        zip(agent_data, commits, true_drifts, frames)
    ):
        assert isinstance(agent_entry, dict), f"Entry {i} must be a JSON object."
        assert "timestamp" in agent_entry, f"Entry {i} missing 'timestamp' key."
        assert "hash" in agent_entry, f"Entry {i} missing 'hash' key."
        assert "drift_score" in agent_entry, f"Entry {i} missing 'drift_score' key."

        timestamp = agent_entry["timestamp"]
        assert isinstance(timestamp, int) and not isinstance(timestamp, bool), (
            f"Entry {i} 'timestamp' must be an integer."
        )
        assert timestamp == commit["timestamp"], (
            f"Entry {i} has timestamp {timestamp}, expected {commit['timestamp']}."
        )

        hash_value = agent_entry["hash"]
        assert isinstance(hash_value, str), f"Entry {i} 'hash' must be a string."

        with Image.open(frame_path) as frame:
            frame = frame.convert("RGB")
            if frame_is_black(frame):
                assert hash_value == "unknown", (
                    f"Entry {i} corresponds to a corrupted frame and must use hash 'unknown'."
                )
            else:
                assert re.fullmatch(r"[0-9a-f]{8}", hash_value), (
                    f"Entry {i} hash must be exactly eight lowercase hexadecimal characters."
                )
                assert rendered_line_matches(frame, timestamp, hash_value), (
                    f"Entry {i} timestamp/hash does not match the diagnostic text in the video."
                )

        agent_drift = agent_entry["drift_score"]
        assert isinstance(agent_drift, (int, float)), (
            f"Entry {i} 'drift_score' must be a number."
        )
        mse += (agent_drift - true_drift) ** 2

    mse /= len(true_drifts)
    threshold = 0.005
    assert mse <= threshold, (
        f"MSE of drift_score is {mse:.6f}, which exceeds the threshold of {threshold}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
