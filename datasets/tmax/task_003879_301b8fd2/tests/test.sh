#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import re
import shutil
import subprocess
import tempfile
import pytest

SEGMENTS_DIR = "/home/user/segments"
FEATURES_PATH = "/home/user/features.csv"
PREDICTIONS_PATH = "/home/user/predictions.csv"
FINAL_PATH = "/home/user/final_result.txt"
NUMBER = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def run_volume_detect(path):
    res = subprocess.run(
        ["ffmpeg", "-nostdin", "-i", path, "-af", "volumedetect", "-f", "null", "/dev/null"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    max_match = re.findall(r"max_volume:\s*([-+]?\d+(?:\.\d+)?)\s*dB", res.stderr)
    mean_match = re.findall(r"mean_volume:\s*([-+]?\d+(?:\.\d+)?)\s*dB", res.stderr)
    if not mean_match:
        return None
    assert max_match, f"volumedetect produced mean_volume but no max_volume for {path}"
    return float(max_match[-1]), float(mean_match[-1])


def duration(path):
    res = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(res.stdout.strip())


def reference_segments_and_predictions():
    tmp = tempfile.mkdtemp(prefix="truth_segments_")
    subprocess.run(
        ["ffmpeg", "-nostdin", "-y", "-i", "/app/recording.wav", "-f", "segment", "-segment_time", "1", "-c", "copy", os.path.join(tmp, "out%03d.wav")],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open("/app/weights.csv", "r") as wf:
        intercept, w_max, w_mean = map(float, wf.read().strip().split(","))

    rows = []
    for path in sorted(glob.glob(os.path.join(tmp, "out*.wav"))):
        values = run_volume_detect(path)
        if values is not None:
            max_v, mean_v = values
            rows.append((max_v, mean_v, intercept + w_max * max_v + w_mean * mean_v))
    shutil.rmtree(tmp)
    assert rows, "Failed to compute truth: no valid segments found in /app/recording.wav"
    return rows, (intercept, w_max, w_mean)


def read_strict_csv(path, expected_header):
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"CSV is empty: {path}"
    assert rows[0] == expected_header, f"Incorrect header in {path}: {rows[0]!r}"
    assert all(len(row) == len(expected_header) for row in rows[1:]), f"Malformed row in {path}"
    return rows[1:]


def test_required_pipeline_artifacts():
    reference, weights = reference_segments_and_predictions()
    intercept, w_max, w_mean = weights

    assert os.path.isdir(SEGMENTS_DIR), f"Missing required directory: {SEGMENTS_DIR}"
    segment_paths = sorted(glob.glob(os.path.join(SEGMENTS_DIR, "*.wav")))
    assert len(segment_paths) == len(reference), (
        f"Expected {len(reference)} one-second WAV segments, found {len(segment_paths)}"
    )
    assert len({os.path.basename(p) for p in segment_paths}) == len(segment_paths)

    durations = [duration(path) for path in segment_paths]
    assert all(0.85 <= value <= 1.15 for value in durations), f"Segments are not approximately one second: {durations}"
    source_duration = duration("/app/recording.wav")
    assert abs(sum(durations) - source_duration) <= 0.15, "Segments do not cover the full recording"

    feature_rows = read_strict_csv(FEATURES_PATH, ["segment_name", "max_volume", "mean_volume"])
    assert len(feature_rows) == len(reference), "features.csv must contain every valid segment exactly once"

    actual_names = {os.path.basename(path) for path in segment_paths}
    feature_names = [row[0] for row in feature_rows]
    assert len(feature_names) == len(set(feature_names)), "Duplicate segment_name in features.csv"
    assert set(feature_names) == actual_names, "features.csv does not correspond exactly to the WAV segments"

    submitted_features = {}
    for name, max_text, mean_text in feature_rows:
        assert NUMBER.fullmatch(max_text), f"Invalid max_volume value for {name}: {max_text!r}"
        assert NUMBER.fullmatch(mean_text), f"Invalid mean_volume value for {name}: {mean_text!r}"
        max_v, mean_v = float(max_text), float(mean_text)
        assert math.isfinite(max_v) and math.isfinite(mean_v), f"Non-finite feature for {name}"
        measured = run_volume_detect(os.path.join(SEGMENTS_DIR, name))
        assert measured is not None, f"Segment {name} has no valid mean_volume"
        measured_max, measured_mean = measured
        assert abs(max_v - measured_max) <= 0.051, f"Incorrect max_volume for {name}"
        assert abs(mean_v - measured_mean) <= 0.051, f"Incorrect mean_volume for {name}"
        submitted_features[name] = (max_v, mean_v)

    # Ensure the submitted segment measurements match the independently split recording.
    unmatched = list((max_v, mean_v) for max_v, mean_v, _ in reference)
    for max_v, mean_v in submitted_features.values():
        for index, (ref_max, ref_mean) in enumerate(unmatched):
            if abs(max_v - ref_max) <= 0.11 and abs(mean_v - ref_mean) <= 0.11:
                unmatched.pop(index)
                break
        else:
            pytest.fail("Segment features do not match the source recording")
    assert not unmatched, "Some source segments are missing from features.csv"

    prediction_rows = read_strict_csv(PREDICTIONS_PATH, ["segment_name", "prediction"])
    assert len(prediction_rows) == len(feature_rows), "predictions.csv must contain one prediction per feature row"
    prediction_names = [row[0] for row in prediction_rows]
    assert len(prediction_names) == len(set(prediction_names)), "Duplicate segment_name in predictions.csv"
    assert set(prediction_names) == set(feature_names), "predictions.csv does not correspond exactly to features.csv"

    predictions = []
    for name, prediction_text in prediction_rows:
        assert NUMBER.fullmatch(prediction_text), f"Invalid prediction for {name}: {prediction_text!r}"
        prediction = float(prediction_text)
        assert math.isfinite(prediction), f"Non-finite prediction for {name}"
        max_v, mean_v = submitted_features[name]
        expected = intercept + w_max * max_v + w_mean * mean_v
        assert abs(prediction - expected) <= 1e-4, f"Incorrect model inference for {name}"
        predictions.append(prediction)

    assert os.path.isfile(FINAL_PATH), f"Missing required file: {FINAL_PATH}"
    with open(FINAL_PATH, "r") as f:
        text = f.read().strip()
    assert NUMBER.fullmatch(text), f"Could not read a single numeric value from {FINAL_PATH}"
    final_value = float(text)
    assert math.isfinite(final_value), "final_result.txt contains a non-finite value"
    # Any average of bootstrap means must remain in the convex hull of the predictions.
    assert min(predictions) - 1e-9 <= final_value <= max(predictions) + 1e-9, (
        "final_result.txt cannot be an average of bootstrap samples from predictions.csv"
    )


def test_bootstrap_mean_accuracy():
    """Preserve the original independent target-metric assertion."""
    assert os.path.exists(FINAL_PATH), f"Missing required file: {FINAL_PATH}"
    try:
        with open(FINAL_PATH, "r") as f:
            agent_val = float(f.read().strip())
    except Exception as exc:
        pytest.fail(f"Could not read a valid numeric value from {FINAL_PATH}. Error: {exc}")

    reference, _ = reference_segments_and_predictions()
    preds = [prediction for _, _, prediction in reference]
    true_mean = sum(preds) / len(preds)
    error = abs(true_mean - agent_val)
    threshold = 0.5
    assert error <= threshold, (
        f"Bootstrap estimate error is too high! True sample mean: {true_mean:.4f}, "
        f"Agent's value: {agent_val:.4f}. Absolute error: {error:.4f} "
        f"(Threshold: <= {threshold})"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
