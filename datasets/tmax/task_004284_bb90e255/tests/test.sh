#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

DETECTOR = "/home/user/detector.sh"
PIPELINE = "/home/user/pipeline.sh"
REPORT = "/home/user/etl_report.csv"
FRAMES_DIR = "/home/user/extracted_frames"
VIDEO = "/app/factory_feed.mp4"
HEADER = ["frame_filename", "is_glitch", "brightness", "fault_probability"]


def run_detector(path):
    result = subprocess.run([DETECTOR, path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    return result.returncode


def image_mean(path):
    result = subprocess.run(
        ["convert", path, "-colorspace", "Gray", "-format", "%[fx:mean*255]", "info:"],
        check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20,
    )
    return float(result.stdout.strip())


def image_dimensions(path):
    result = subprocess.run(
        ["identify", "-format", "%w %h", path], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
    )
    return tuple(map(int, result.stdout.split()))


def test_detector_adversarial_corpus():
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector script {DETECTOR} is not executable"

    # Retain checks over all supplied corpora.
    for root, expected in [
        ("/app/training_data/evil_corpus", 1),
        ("/app/training_data/clean_corpus", 0),
        ("/app/test_data/evil_corpus", 1),
        ("/app/test_data/clean_corpus", 0),
    ]:
        assert os.path.isdir(root), f"Corpus directory missing: {root}"
        files = sorted(os.path.join(root, f) for f in os.listdir(root) if f.endswith(".jpg"))
        assert files, f"No JPEG files found in {root}"
        wrong = [os.path.basename(f) for f in files if run_detector(f) != expected]
        assert not wrong, f"Detector misclassified files in {root}: {', '.join(wrong)}"

    # Content-derived probes use unpredictable, label-neutral paths so the
    # detector cannot classify by clean_corpus/evil_corpus in its argument.
    probe_dir = tempfile.mkdtemp(prefix="frame_probe_")
    try:
        probes = []
        specifications = [
            (0, "gray(50)", "73x61"),
            (0, "gray(100)", "81x67"),
            (0, "gray(150)", "69x83"),
            (0, "gray(220)", "77x59"),
            (1, "black", "71x63"),
            (1, "black", "85x57"),
        ]
        for expected, color, size in specifications:
            path = os.path.join(probe_dir, uuid.uuid4().hex + ".jpg")
            subprocess.run(["convert", "-size", size, f"xc:{color}", path], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            probes.append((path, expected))
        random.SystemRandom().shuffle(probes)
        failures = []
        for path, expected in probes:
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected exit {expected}, got {actual}")
        assert not failures, "Neutral-path detector probes failed: " + "; ".join(failures)
    finally:
        shutil.rmtree(probe_dir, ignore_errors=True)


def test_pipeline_execution_extraction_report_and_bayes():
    assert os.path.isfile(PIPELINE), f"ETL pipeline not found at {PIPELINE}"
    assert os.path.isfile(VIDEO), f"Factory video not found at {VIDEO}"

    # Independently extract the required 1-fps sequence before running the
    # submitted pipeline. These frames supply expected names and image values.
    reference_dir = tempfile.mkdtemp(prefix="reference_frames_")
    try:
        reference_pattern = os.path.join(reference_dir, "frame_%04d.jpg")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", VIDEO,
             "-vf", "fps=1", "-start_number", "1", reference_pattern],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
        )
        expected_names = sorted(
            f for f in os.listdir(reference_dir)
            if re.fullmatch(r"frame_[0-9]{4}\.jpg", f)
        )
        assert expected_names, "Independent extraction produced no frames"

        reference_mean = {
            name: image_mean(os.path.join(reference_dir, name)) for name in expected_names
        }
        reference_dims = {
            name: image_dimensions(os.path.join(reference_dir, name)) for name in expected_names
        }
        # In the supplied feed, blackout frames are the near-black glitches;
        # gray-50 frames are valid observed events.
        expected_glitch = {name: reference_mean[name] < 10.0 for name in expected_names}
        assert any(expected_glitch.values()), "Reference feed contains no glitch frames"
        assert any((not expected_glitch[n]) and reference_mean[n] < 100 for n in expected_names), \
            "Reference feed contains no valid observed-event frames"

        # Remove every possible precomputed result, then execute the requested
        # Bash ETL artifact against the actual factory video.
        if os.path.lexists(FRAMES_DIR):
            if os.path.isdir(FRAMES_DIR) and not os.path.islink(FRAMES_DIR):
                shutil.rmtree(FRAMES_DIR)
            else:
                os.unlink(FRAMES_DIR)
        if os.path.lexists(REPORT):
            os.unlink(REPORT)

        result = subprocess.run(
            ["bash", PIPELINE], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
        )
        assert result.returncode == 0, \
            f"pipeline.sh failed with exit {result.returncode}: {result.stderr[-2000:]}"

        assert os.path.isdir(FRAMES_DIR), "Pipeline did not create extracted_frames/"
        assert os.path.isfile(REPORT), "Pipeline did not generate etl_report.csv"

        remaining_names = sorted(
            f for f in os.listdir(FRAMES_DIR)
            if re.fullmatch(r"frame_[0-9]{4}\.jpg", f)
        )
        expected_remaining = [n for n in expected_names if not expected_glitch[n]]
        assert remaining_names == expected_remaining, \
            f"Wrong retained frame set. Expected {expected_remaining}, got {remaining_names}"

        # Retained files must be valid images corresponding to the independently
        # extracted frame at that timestamp, rather than arbitrary placeholders.
        for name in expected_remaining:
            actual_path = os.path.join(FRAMES_DIR, name)
            assert image_dimensions(actual_path) == reference_dims[name], \
                f"Dimensions differ for retained frame {name}"
            assert abs(image_mean(actual_path) - reference_mean[name]) <= 3.0, \
                f"Image content/brightness differs for retained frame {name}"

        with open(REPORT, newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader, None)
            assert header == HEADER, f"CSV header is incorrect. Got: {header}"
            rows = list(reader)

        # Retain the original format assertions, strengthened to require exactly
        # one ordered row for every independently extracted frame.
        assert len(rows) >= 15, f"Expected at least 15 frames in the report, got {len(rows)}"
        assert len(rows) == len(expected_names), \
            f"Expected exactly {len(expected_names)} report rows, got {len(rows)}"
        assert [row[0] for row in rows if row] == expected_names, \
            "Report filenames do not exactly match the extracted 1-fps sequence"

        p_fault_from_report = 0.05
        p_fault_expected = 0.05
        for i, (row, expected_name) in enumerate(zip(rows, expected_names), start=1):
            assert len(row) == 4, f"Row {i} does not have exactly 4 columns: {row}"
            frame_filename, is_glitch, brightness, probability_text = row
            assert frame_filename == expected_name
            assert is_glitch in ("0", "1"), f"Invalid is_glitch at row {i}: {is_glitch}"

            should_glitch = expected_glitch[expected_name]
            assert is_glitch == ("1" if should_glitch else "0"), \
                f"Incorrect glitch result for {expected_name}"

            if is_glitch == "1":
                assert brightness == "NA", f"Glitch frame must have NA brightness at row {i}"
            else:
                assert brightness.isdigit(), f"Valid frame must have integer brightness at row {i}"
                reported_brightness = int(brightness)
                assert 0 <= reported_brightness <= 255
                assert abs(reported_brightness - reference_mean[expected_name]) <= 1.0, \
                    f"Brightness for {expected_name} was not derived from its frame"

            try:
                reported_probability = float(probability_text)
            except ValueError:
                raise AssertionError(f"Invalid fault_probability at row {i}: {probability_text}")
            assert math.isfinite(reported_probability)

            # Preserve the original Bayesian assertion using reported fields.
            if is_glitch == "0":
                event = int(brightness) < 100
                likelihood_fault = 0.8 if event else 0.2
                likelihood_no_fault = 0.1 if event else 0.9
                denominator = (likelihood_fault * p_fault_from_report +
                               likelihood_no_fault * (1 - p_fault_from_report))
                p_fault_from_report = likelihood_fault * p_fault_from_report / denominator
            assert math.isclose(reported_probability, round(p_fault_from_report, 4), abs_tol=1e-4), \
                f"Row {i}: Bayesian update does not match reported fields"

            # Also derive the expected update from the actual video, so fabricated
            # glitch/brightness fields cannot make a self-consistent report pass.
            if not should_glitch:
                event = reference_mean[expected_name] < 100.0
                likelihood_fault = 0.8 if event else 0.2
                likelihood_no_fault = 0.1 if event else 0.9
                denominator = (likelihood_fault * p_fault_expected +
                               likelihood_no_fault * (1 - p_fault_expected))
                p_fault_expected = likelihood_fault * p_fault_expected / denominator
            assert math.isclose(reported_probability, round(p_fault_expected, 4), abs_tol=1e-4), \
                f"Row {i} ({expected_name}): expected {round(p_fault_expected, 4)}, got {reported_probability}"
    finally:
        shutil.rmtree(reference_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
