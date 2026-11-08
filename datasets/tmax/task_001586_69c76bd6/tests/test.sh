#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import subprocess
import tempfile
import uuid

import pytest


def read_embedded_telemetry(video_path):
    result = subprocess.run(
        [
            "/usr/bin/ffprobe", "-v", "error", "-show_entries", "format_tags",
            "-of", "json", video_path,
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    probe = json.loads(result.stdout)
    tags = probe.get("format", {}).get("tags", {})
    tags = {str(k).lower(): v for k, v in tags.items()}
    assert "telemetry_frames" in tags, "Video has no telemetry_frames metadata"
    data = json.loads(tags["telemetry_frames"])
    assert isinstance(data, list)
    return data


def assert_same_numbers(actual, expected):
    assert isinstance(actual, list), "Extractor output must be a JSON list"
    assert len(actual) == len(expected), "Extractor did not preserve the full sequence"
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert not isinstance(got, bool), f"Boolean at telemetry index {index}"
        try:
            got_number = float(got)
            wanted_number = float(wanted)
        except (TypeError, ValueError):
            pytest.fail(f"Non-numeric telemetry value at index {index}: {got!r}")
        if math.isnan(wanted_number):
            assert math.isnan(got_number), f"Expected NaN at index {index}"
        elif math.isinf(wanted_number):
            assert math.isinf(got_number) and ((got_number > 0) == (wanted_number > 0)), \
                f"Incorrect infinity at index {index}"
        else:
            assert got_number == wanted_number, \
                f"Telemetry mismatch at index {index}: {got!r} != {wanted!r}"


def run_extractor(video_path):
    extractor_path = "/app/extract_telemetry.py"
    payload_path = "/app/extracted_payload.json"
    assert os.path.isfile(extractor_path), f"Missing extraction script: {extractor_path}"
    if os.path.exists(payload_path):
        os.unlink(payload_path)
    result = subprocess.run(
        ["python3", extractor_path, video_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"Extractor failed with code {result.returncode}: {result.stderr}"
    assert os.path.isfile(payload_path), "Extractor did not create /app/extracted_payload.json"
    with open(payload_path, "r") as f:
        return json.load(f)


def make_metadata_video(path, telemetry):
    metadata = json.dumps(telemetry, separators=(",", ":"))
    result = subprocess.run(
        [
            "/usr/bin/ffmpeg", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=black:s=32x32:r=4",
            "-t", "1", "-c:v", "mpeg4", "-pix_fmt", "yuv420p",
            "-movflags", "use_metadata_tags",
            "-metadata", f"telemetry_frames={metadata}",
            path,
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr


def test_extractor_executes_and_extracts_video_metadata():
    captured = "/app/exfiltration_capture.mp4"
    expected = read_embedded_telemetry(captured)
    actual = run_extractor(captured)
    assert_same_numbers(actual, expected)

    rng = random.Random(os.urandom(16))
    challenge = [rng.uniform(-100.0, 100.0) for _ in range(64)]
    challenge[5] = 1e-310
    challenge[23] = float("inf")
    challenge[41] = float("nan")
    with tempfile.TemporaryDirectory() as directory:
        challenge_video = os.path.join(directory, "capture.mp4")
        make_metadata_video(challenge_video, challenge)
        derived_expected = read_embedded_telemetry(challenge_video)
        challenge_actual = run_extractor(challenge_video)
        assert_same_numbers(challenge_actual, derived_expected)

    # Leave the required output corresponding to the supplied capture.
    final_actual = run_extractor(captured)
    assert_same_numbers(final_actual, expected)


def test_extracted_payload_exists_and_valid():
    payload_path = "/app/extracted_payload.json"
    assert os.path.isfile(payload_path), f"Missing extracted payload: {payload_path}"

    with open(payload_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {payload_path} is not valid JSON.")

    assert isinstance(data, list), f"Expected {payload_path} to contain a JSON list."
    # We expect the list to contain numbers or strings representing numbers (e.g., denormalized floats)
    assert len(data) > 0, f"Extracted payload is empty."


def test_detector_clean_corpus():
    detector_path = "/app/detector.py"
    assert os.path.isfile(detector_path), f"Missing detector script: {detector_path}"

    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run(["python3", detector_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (expected exit code 0). Offending files: {', '.join(failed_files[:10])}")


def test_detector_evil_corpus():
    detector_path = "/app/detector.py"
    assert os.path.isfile(detector_path), f"Missing detector script: {detector_path}"

    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run(["python3", detector_path, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1). Offending files: {', '.join(failed_files[:10])}")


def test_detector_on_neutral_paths_and_fresh_payloads():
    detector_path = "/app/detector.py"
    assert os.path.isfile(detector_path), f"Missing detector script: {detector_path}"
    rng = random.Random(os.urandom(16))

    with tempfile.TemporaryDirectory() as directory:
        cases = []
        for _ in range(12):
            clean = [rng.uniform(-100.0, 100.0) for _ in range(64)]
            cases.append((clean, 0))

            evil = [rng.uniform(-100.0, 100.0) for _ in range(64)]
            evil[10] = 1e-310
            evil[20] = float("inf")
            evil[30] = float("nan")
            cases.append((evil, 1))

        rng.shuffle(cases)
        for payload, expected_code in cases:
            path = os.path.join(directory, f"input_{uuid.uuid4().hex}.json")
            with open(path, "w") as f:
                json.dump(payload, f)
            result = subprocess.run(
                ["python3", detector_path, path],
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == expected_code, \
                f"Detector returned {result.returncode}, expected {expected_code}, for a neutral-path payload"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
