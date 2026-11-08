#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/filter_data.sh"
FINAL = "/home/user/final_output.csv"
WEIGHTS = (0.5, -0.2, 0.1, 1.5, -50.0)


def score(r, g, b, speed):
    wr, wg, wb, ws, bias = WEIGHTS
    return wr*r + wg*g + wb*b + ws*speed + bias


def run_filter(path):
    result = subprocess.run(
        [SCRIPT, path], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, result.stderr
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert clean_files, f"No clean corpus files found in {clean_dir}"
    assert evil_files, f"No evil corpus files found in {evil_dir}"

    clean_modified = []
    evil_bypassed = []

    for path in clean_files:
        with open(path) as f:
            expected = sorted(line.strip() for line in f if line.strip())
        if sorted(run_filter(path)) != expected:
            clean_modified.append(os.path.basename(path))

    for path in evil_files:
        if run_filter(path):
            evil_bypassed.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_mixed_rows_use_model_not_path():
    rng = random.SystemRandom()
    rows = []
    clean_count = evil_count = 0
    frame = 1000

    # Generate previously unseen clean and anomalous rows in one neutrally named file.
    while clean_count < 40 or evil_count < 40:
        r = round(rng.uniform(0, 255), 6)
        g = round(rng.uniform(0, 255), 6)
        b = round(rng.uniform(0, 255), 6)
        speed = round(rng.uniform(-20, 100), 6)
        temperature = round(rng.uniform(-10, 120), 6)
        s = score(r, g, b, speed)
        is_clean = s <= 0
        if (is_clean and clean_count >= 40) or (not is_clean and evil_count >= 40):
            continue
        line = f"{frame},{r:.6f},{g:.6f},{b:.6f},{speed:.6f},{temperature:.6f}"
        rows.append((line, is_clean))
        clean_count += int(is_clean)
        evil_count += int(not is_clean)
        frame += 1

    rng.shuffle(rows)
    expected = [line for line, is_clean in rows if is_clean]
    with tempfile.TemporaryDirectory(prefix="telemetry-check-") as directory:
        path = os.path.join(directory, f"batch-{rng.randrange(1 << 60):x}.csv")
        with open(path, "w") as f:
            f.write("\n".join(line for line, _ in rows) + "\n")
        assert run_filter(path) == expected


def extract_video_features():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
         "/app/traffic.mp4"],
        capture_output=True, text=True, check=True, timeout=20
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/traffic.mp4", "-vf", "fps=1",
         "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        capture_output=True, check=True, timeout=60
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0
    features = []
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        pixels = width * height
        features.append((
            sum(frame[0::3]) / pixels,
            sum(frame[1::3]) / pixels,
            sum(frame[2::3]) / pixels,
        ))
    assert features, "No frames were extracted from the video"
    return features


def expected_pipeline_rows():
    features = extract_video_features()
    telemetry = {}
    with open("/app/telemetry.csv", newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            telemetry[int(row[0])] = (float(row[1]), float(row[2]))

    joined = []
    for index, (r, g, b) in enumerate(features, 1):
        if index in telemetry:
            speed, temperature = telemetry[index]
            joined.append((index, r, g, b, speed, temperature))
    assert joined, "Video and telemetry produced no joined rows"
    return joined, [row for row in joined if score(row[1], row[2], row[3], row[4]) <= 0]


def test_filter_on_independently_extracted_video_rows():
    joined, expected_clean = expected_pipeline_rows()
    lines = [f"{i},{r:.6f},{g:.6f},{b:.6f},{speed:g},{temp:g}"
             for i, r, g, b, speed, temp in joined]
    expected = [line for line, row in zip(lines, joined)
                if score(row[1], row[2], row[3], row[4]) <= 0]
    with tempfile.TemporaryDirectory(prefix="video-join-") as directory:
        path = os.path.join(directory, "joined-input.csv")
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        assert run_filter(path) == expected


def test_final_output_matches_video_and_telemetry():
    assert os.path.isfile(FINAL), f"Final output {FINAL} is missing."
    _, expected = expected_pipeline_rows()
    with open(FINAL, newline="") as f:
        actual = [row for row in csv.reader(f) if row]

    assert len(actual) == len(expected), "Final output has the wrong number of clean rows"
    for fields, wanted in zip(actual, expected):
        assert len(fields) == 6, "Final output must contain six comma-separated columns"
        try:
            values = [float(value.strip()) for value in fields]
        except ValueError:
            pytest.fail("Final output contains a header or non-numeric value")
        index, r, g, b, speed, temperature = wanted
        assert values[0] == index
        # Decimal formatting is unspecified, so permit rounding to the nearest integer.
        assert abs(values[1] - r) <= 0.51
        assert abs(values[2] - g) <= 0.51
        assert abs(values[3] - b) <= 0.51
        assert abs(values[4] - speed) <= 1e-6
        assert abs(values[5] - temperature) <= 1e-6
        assert score(values[1], values[2], values[3], values[4]) <= 1.0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
