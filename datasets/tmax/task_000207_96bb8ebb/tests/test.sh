#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile

import pytest

CLASSIFIER = "/home/user/classifier"


def test_video_stats():
    stats_file = "/home/user/video_stats.txt"
    assert os.path.isfile(stats_file), f"Missing video stats file at {stats_file}"

    with open(stats_file, "r") as f:
        content = f.read().strip()

    parts = content.split(",")
    assert len(parts) == 2, f"Expected format 'total_frames,avg_intensity', got: {content}"

    try:
        total_frames = int(parts[0].strip())
        avg_intensity = float(parts[1].strip())
    except ValueError:
        pytest.fail(f"Could not parse integers/floats from video stats: {content}")

    assert total_frames == 150, f"Expected 150 frames, got {total_frames}"
    assert 111.0 <= avg_intensity <= 114.0, f"Expected average intensity around 112.4, got {avg_intensity}"


def test_classifier_compiled():
    assert os.path.isfile(CLASSIFIER), f"Missing compiled classifier at {CLASSIFIER}"
    assert os.access(CLASSIFIER, os.X_OK), f"Classifier at {CLASSIFIER} is not executable"
    with open(CLASSIFIER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Classifier must be a compiled native executable"


def run_classifier_and_get_predictions(target_dir):
    with tempfile.TemporaryDirectory(prefix="classifier-output-") as work_dir:
        result = subprocess.run(
            [CLASSIFIER, target_dir],
            cwd=work_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Classifier failed on {target_dir} with error: {result.stderr}"
        )

        predictions_file = os.path.join(work_dir, "predictions.txt")
        assert os.path.isfile(predictions_file), (
            f"Classifier did not produce predictions.txt for {target_dir}"
        )

        predictions = {}
        with open(predictions_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(",")
                if len(parts) == 2:
                    predictions[parts[0].strip()] = parts[1].strip()
        return predictions


def test_classifier_clean_corpus():
    clean_dir = "/app/hidden_test/clean/"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory at {clean_dir}"

    csv_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
    assert len(csv_files) > 0, f"No CSV files found in {clean_dir}"

    predictions = run_classifier_and_get_predictions(clean_dir)

    modified = []
    for filename in csv_files:
        if filename not in predictions:
            modified.append(f"{filename} (missing prediction)")
        elif predictions[filename] != "0":
            modified.append(f"{filename} (predicted {predictions[filename]})")

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(csv_files)} clean modified/rejected. "
            f"Offending files: {', '.join(modified[:10])}"
        )


def test_classifier_evil_corpus():
    evil_dir = "/app/hidden_test/evil/"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory at {evil_dir}"

    csv_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert len(csv_files) > 0, f"No CSV files found in {evil_dir}"

    predictions = run_classifier_and_get_predictions(evil_dir)

    bypassed = []
    for filename in csv_files:
        if filename not in predictions:
            bypassed.append(f"{filename} (missing prediction)")
        elif predictions[filename] != "1":
            bypassed.append(f"{filename} (predicted {predictions[filename]})")

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(csv_files)} evil bypassed. "
            f"Offending files: {', '.join(bypassed[:10])}"
        )


def bounded_gaussian(rng, scale):
    while True:
        value = rng.gauss(0.0, scale)
        if abs(value) < 90.0:
            return value


def test_classifier_on_runtime_generated_mixed_corpus():
    rng = random.Random(int.from_bytes(os.urandom(32), "big"))

    with tempfile.TemporaryDirectory(prefix="evaluation-corpus-") as corpus_dir:
        expected = {}
        labels = [0] * 16 + [1] * 16
        rng.shuffle(labels)

        for label in labels:
            filename = f"item_{secrets.token_hex(12)}.csv"
            expected[filename] = str(label)
            path = os.path.join(corpus_dir, filename)

            with open(path, "w", newline="") as f:
                writer = csv.writer(f, lineterminator="\n")
                for _ in range(100):
                    row = [bounded_gaussian(rng, 1.0) for _ in range(3)]
                    variance_scale = 5.0 if label == 1 else 1.0
                    row.extend(bounded_gaussian(rng, variance_scale) for _ in range(2))
                    # Fixed-width fields prevent file length from revealing the label.
                    writer.writerow([f"{value:+018.10f}" for value in row])

        predictions = run_classifier_and_get_predictions(corpus_dir + os.sep)

        errors = []
        for filename, wanted in expected.items():
            actual = predictions.get(filename)
            if actual != wanted:
                errors.append(f"{filename}: expected {wanted}, got {actual!r}")

        if errors:
            pytest.fail(
                f"Classifier failed {len(errors)} of {len(expected)} runtime-generated "
                f"mixed samples: {', '.join(errors[:10])}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
