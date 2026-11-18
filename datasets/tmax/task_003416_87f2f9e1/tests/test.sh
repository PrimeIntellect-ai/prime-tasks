#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import statistics
import string
import subprocess
import tempfile

import cv2
import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"
CLEAN_DIR = "/app/verifier/clean_logs"
EVIL_DIR = "/app/verifier/evil_logs"
VIDEO_PATH = "/app/dashboard.mp4"
VIDEO_START = 1710000000


def run_sanitizer(input_dir, output_dir):
    assert os.path.exists(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer path is not a file: {SCRIPT_PATH}"
    cmd = ["python3", SCRIPT_PATH, "--input_dir", input_dir, "--output_dir", output_dir]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        pytest.fail("Sanitizer timed out")
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_adversarial_corpora():
    if not os.path.exists(CLEAN_DIR) or not os.path.exists(EVIL_DIR):
        pytest.fail("Corpus directories are missing.")

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        run_sanitizer(CLEAN_DIR, clean_out)
        run_sanitizer(EVIL_DIR, evil_out)

        clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.log')]
        evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.log')]
        clean_modified = []
        evil_bypassed = []

        for fname in clean_files:
            orig_path = os.path.join(CLEAN_DIR, fname)
            out_path = os.path.join(clean_out, fname)
            if not os.path.exists(out_path):
                clean_modified.append(fname)
                continue
            with open(orig_path, 'r', encoding='utf-8') as f:
                orig_lines = f.readlines()
            with open(out_path, 'r', encoding='utf-8') as f:
                out_lines = f.readlines()
            if orig_lines != out_lines:
                clean_modified.append(fname)

        for fname in evil_files:
            orig_path = os.path.join(EVIL_DIR, fname)
            out_path = os.path.join(evil_out, fname)
            if not os.path.exists(out_path):
                continue
            with open(orig_path, 'r', encoding='utf-8') as f:
                orig_lines = f.readlines()
            with open(out_path, 'r', encoding='utf-8') as f:
                out_lines = f.readlines()

            evil_lines_present = False
            for line in out_lines:
                if "attack" in line.lower() and "userB" in line:
                    evil_lines_present = True
                if "userC" in line:
                    evil_lines_present = True
                if "dropped because stddev" in line:
                    evil_lines_present = True
                if "Paypаl" in line or "admіn" in line:
                    evil_lines_present = True
            if evil_lines_present:
                evil_bypassed.append(fname)

        errors = []
        if evil_bypassed:
            errors.append(
                f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
                + ", ".join(evil_bypassed)
            )
        if clean_modified:
            errors.append(
                f"{len(clean_modified)} of {len(clean_files)} clean modified: "
                + ", ".join(clean_modified)
            )
        if errors:
            pytest.fail(" | ".join(errors))


def active_seconds_from_video():
    assert os.path.isfile(VIDEO_PATH), "Dashboard video is missing"
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), "Could not open dashboard video"
    active = set()
    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        assert frame.shape[0] >= 10 and frame.shape[1] >= 10
        block = frame[:10, :10]
        blue, green, red = block.mean(axis=(0, 1))
        if red > 200 and green < 50 and blue < 50:
            active.add(VIDEO_START + frame_index)
        frame_index += 1
    cap.release()
    assert frame_index == 120, f"Expected 120 frames, found {frame_index}"
    assert active, "No attack frames detected in dashboard video"
    assert len(active) < frame_index, "Every video frame was classified as an attack"
    return active


def random_id(prefix):
    return prefix + secrets.token_hex(8)


def has_mixed_word(message):
    for word in message.split(' '):
        latin = any(('A' <= ch <= 'Z') or ('a' <= ch <= 'z') for ch in word)
        cyrillic = any(
            ('А' <= ch <= 'Я') or ('а' <= ch <= 'я') or ch in ('Ё', 'ё')
            for ch in word
        )
        if latin and cyrillic:
            return True
    return False


def expected_lines(lines, active_seconds):
    histories = {}
    kept = []
    for line in lines:
        timestamp_text, user_id, message_with_newline = line.split(' | ', 2)
        timestamp_ms = int(timestamp_text)
        message = message_with_newline.rstrip('\r\n')

        history = histories.setdefault(user_id, [])
        history.append(timestamp_ms)
        if len(history) > 5:
            del history[:-5]

        rolling_anomaly = False
        if len(history) == 5:
            differences = [history[i] - history[i - 1] for i in range(1, 5)]
            rolling_anomaly = statistics.stdev(differences) < 100.0

        attack = timestamp_ms // 1000 in active_seconds
        unicode_attack = has_mixed_word(message)
        if not (attack or rolling_anomaly or unicode_attack):
            kept.append(line)
    return kept


def test_generated_behavior_against_all_rules():
    active = active_seconds_from_video()
    all_video_seconds = [VIDEO_START + i for i in range(120)]
    latin_letters = string.ascii_letters
    cyrillic_letters = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя"

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        corpora = {}

        video_lines = []
        for second in all_video_seconds:
            uid = random_id("v")
            offset = secrets.randbelow(1000)
            message = "ordinary " + ''.join(secrets.choice(latin_letters) for _ in range(14))
            video_lines.append(f"{second * 1000 + offset} | {uid} | {message}\n")
        corpora[random_id("video_") + ".log"] = video_lines

        unicode_lines = []
        unicode_base = (VIDEO_START + 200) * 1000 + secrets.randbelow(300)
        for i in range(12):
            left = ''.join(secrets.choice(latin_letters) for _ in range(5))
            middle = ''.join(secrets.choice(cyrillic_letters) for _ in range(3))
            right = ''.join(secrets.choice(latin_letters) for _ in range(4))
            mixed = left + middle + right
            unicode_lines.append(
                f"{unicode_base + i * 1700} | {random_id('m')} | token {mixed} accepted\n"
            )
        pure_latin = ''.join(secrets.choice(latin_letters) for _ in range(14))
        pure_cyrillic = ''.join(secrets.choice(cyrillic_letters) for _ in range(14))
        unicode_lines.append(
            f"{unicode_base + 30000} | {random_id('p')} | {pure_latin} {pure_cyrillic}\n"
        )
        unicode_lines.append(
            f"{unicode_base + 32000} | {random_id('p')} | {pure_cyrillic} {pure_latin}\n"
        )
        corpora[random_id("unicode_") + ".log"] = unicode_lines

        rolling_entries = []
        rolling_base = (VIDEO_START + 400) * 1000 + secrets.randbelow(200)

        user_window = random_id("r")
        interval = 700 + secrets.randbelow(700)
        timestamp = rolling_base
        rolling_entries.append((timestamp, user_window, "window start"))
        for i in range(1, 5):
            timestamp += interval
            rolling_entries.append((timestamp, user_window, f"mechanical {i}"))
        timestamp += interval + 600
        rolling_entries.append((timestamp, user_window, "variance reset"))
        for i in range(4):
            timestamp += interval
            rolling_entries.append((timestamp, user_window, f"new window {i}"))

        user_boundary = random_id("b")
        boundary_interval = 900 + secrets.randbelow(500)
        timestamp = rolling_base + 250
        rolling_entries.append((timestamp, user_boundary, "boundary start"))
        for i, difference in enumerate([
            boundary_interval - 50,
            boundary_interval - 50,
            boundary_interval - 50,
            boundary_interval + 150,
        ]):
            timestamp += difference
            rolling_entries.append((timestamp, user_boundary, f"boundary {i}"))

        user_below = random_id("s")
        below_interval = 950 + secrets.randbelow(500)
        timestamp = rolling_base + 500
        rolling_entries.append((timestamp, user_below, "below start"))
        for i, difference in enumerate([
            below_interval - 40,
            below_interval - 40,
            below_interval - 40,
            below_interval + 120,
        ]):
            timestamp += difference
            rolling_entries.append((timestamp, user_below, f"below {i}"))

        rolling_entries.sort(key=lambda item: item[0])
        rolling_lines = [
            f"{timestamp} | {uid} | {message}\n"
            for timestamp, uid, message in rolling_entries
        ]
        corpora[random_id("rolling_") + ".log"] = rolling_lines

        for filename, lines in corpora.items():
            with open(os.path.join(input_dir, filename), 'w', encoding='utf-8', newline='') as f:
                f.writelines(lines)

        run_sanitizer(input_dir, output_dir)

        expected_names = set(corpora)
        actual_names = {name for name in os.listdir(output_dir) if name.endswith('.log')}
        assert actual_names == expected_names, (
            f"Output .log filenames differ: expected {sorted(expected_names)}, "
            f"found {sorted(actual_names)}"
        )

        for filename, original in corpora.items():
            output_path = os.path.join(output_dir, filename)
            assert os.path.isfile(output_path), f"Missing output file {filename}"
            with open(output_path, 'r', encoding='utf-8', newline='') as f:
                actual = f.readlines()
            expected = expected_lines(original, active)
            assert actual == expected, f"Incorrect sanitized content for {filename}"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
