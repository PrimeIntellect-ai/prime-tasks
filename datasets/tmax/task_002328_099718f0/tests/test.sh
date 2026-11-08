#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

PIPELINE = "/home/user/run_pipeline.sh"
JSON_PATH = "/home/user/video_analysis.json"
FILTER = "/home/user/filter_transcripts.py"
VIDEO = "/app/experiment_record.mp4"


def run_pipeline():
    result = subprocess.run(
        [PIPELINE], capture_output=True, text=True, stdin=subprocess.DEVNULL,
        timeout=180
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_analysis():
    assert os.path.isfile(JSON_PATH), f"JSON output missing at {JSON_PATH}"
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {JSON_PATH} is not valid JSON.")
    expected_keys = {"total_frames", "blank_frames", "ci_lower", "ci_upper"}
    assert set(data.keys()) == expected_keys, (
        f"JSON keys mismatch. Expected {expected_keys}, got {set(data.keys())}"
    )
    return data


def decoded_counts(path):
    capture = cv2.VideoCapture(path)
    total = 0
    blank = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        total += 1
        if float(np.std(frame)) < 2.0:
            blank += 1
    capture.release()
    return total, blank


def wilson_interval(successes, total, z=1.96):
    p = successes / total
    denominator = 1.0 + z * z / total
    center = (p + z * z / (2.0 * total)) / denominator
    half = z * math.sqrt(p * (1.0 - p) / total + z * z / (4.0 * total * total)) / denominator
    return center - half, center + half


@pytest.fixture(scope="session", autouse=True)
def exercise_full_pipeline():
    assert os.path.isfile(PIPELINE), f"Pipeline script missing at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script at {PIPELINE} is not executable."
    assert os.path.isfile(FILTER), f"Filter script missing at {FILTER}"

    r_scripts = []
    frame_python_scripts = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if name.lower().endswith(".r"):
                r_scripts.append(path)
            if name.endswith(".py") and os.path.abspath(path) != FILTER:
                frame_python_scripts.append(path)
    assert r_scripts, "No R script was provided for the Wilson interval calculation."
    assert frame_python_scripts, "No separate Python frame-analysis script was provided."

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_pipeline()

    original = load_analysis()
    assert original["total_frames"] == 120, f"Expected total_frames=120, got {original['total_frames']}"
    assert original["blank_frames"] == 18, f"Expected blank_frames=18, got {original['blank_frames']}"
    assert math.isclose(original["ci_lower"], 0.0965, abs_tol=1e-4), (
        f"Expected ci_lower~0.0965, got {original['ci_lower']}"
    )
    assert math.isclose(original["ci_upper"], 0.2256, abs_tol=1e-4), (
        f"Expected ci_upper~0.2256, got {original['ci_upper']}"
    )

    with tempfile.TemporaryDirectory() as tmp:
        backup = os.path.join(tmp, "experiment_record.mp4")
        shutil.copy2(VIDEO, backup)
        try:
            frame_count = 43 + secrets.randbelow(7)
            blank_count = 9 + secrets.randbelow(4)
            blank_indices = set(secrets.SystemRandom().sample(range(frame_count), blank_count))
            writer = cv2.VideoWriter(VIDEO, cv2.VideoWriter_fourcc(*"mp4v"), 17, (160, 120))
            assert writer.isOpened(), "Could not create verifier video"
            rng = np.random.default_rng(secrets.randbits(64))
            for index in range(frame_count):
                if index in blank_indices:
                    frame = np.zeros((120, 160, 3), dtype=np.uint8)
                else:
                    frame = rng.integers(25, 231, (120, 160, 3), dtype=np.uint8)
                writer.write(frame)
            writer.release()

            expected_total, expected_blank = decoded_counts(VIDEO)
            assert expected_total > 0
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
            run_pipeline()
            dynamic = load_analysis()
            assert dynamic["total_frames"] == expected_total
            assert dynamic["blank_frames"] == expected_blank
            lower, upper = wilson_interval(expected_blank, expected_total)
            # Allow the small approximation used by the original fixture while
            # still requiring a data-dependent Wilson calculation.
            assert math.isclose(float(dynamic["ci_lower"]), lower, abs_tol=0.002)
            assert math.isclose(float(dynamic["ci_upper"]), upper, abs_tol=0.002)
        finally:
            shutil.copy2(backup, VIDEO)
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
            run_pipeline()


def test_video_analysis_json():
    data = load_analysis()
    assert data["total_frames"] == 120, f"Expected total_frames=120, got {data['total_frames']}"
    assert data["blank_frames"] == 18, f"Expected blank_frames=18, got {data['blank_frames']}"
    assert math.isclose(data["ci_lower"], 0.0965, abs_tol=1e-4), f"Expected ci_lower~0.0965, got {data['ci_lower']}"
    assert math.isclose(data["ci_upper"], 0.2256, abs_tol=1e-4), f"Expected ci_upper~0.2256, got {data['ci_upper']}"


def test_run_pipeline_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"Pipeline script missing at {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK), f"Pipeline script at {PIPELINE} is not executable."


def test_filter_transcripts_script_exists():
    assert os.path.isfile(FILTER), f"Filter script missing at {FILTER}"


def test_adversarial_corpus_filtering():
    evil_corpus = "/app/test_corpus/evil/"
    clean_corpus = "/app/test_corpus/clean/"
    assert os.path.isdir(evil_corpus), f"Evil corpus missing at {evil_corpus}"
    assert os.path.isdir(clean_corpus), f"Clean corpus missing at {clean_corpus}"

    evil_files = [f for f in os.listdir(evil_corpus) if f.endswith(".txt")]
    clean_files = [f for f in os.listdir(clean_corpus) if f.endswith(".txt")]

    with tempfile.TemporaryDirectory() as evil_out, tempfile.TemporaryDirectory() as clean_out:
        result_evil = subprocess.run(["python3", FILTER, evil_corpus, evil_out], capture_output=True, text=True)
        assert result_evil.returncode == 0, f"Script failed on evil corpus:\n{result_evil.stderr}"
        result_clean = subprocess.run(["python3", FILTER, clean_corpus, clean_out], capture_output=True, text=True)
        assert result_clean.returncode == 0, f"Script failed on clean corpus:\n{result_clean.stderr}"

        evil_out_files = set(os.listdir(evil_out))
        clean_out_files = set(os.listdir(clean_out))
        expected_clean_files = set(clean_files)
        missing_clean = expected_clean_files - clean_out_files
        errors = []
        if evil_out_files:
            errors.append(f"{len(evil_out_files)} of {len(evil_files)} evil bypassed (e.g. {list(evil_out_files)[:5]})")
        if missing_clean:
            errors.append(f"{len(missing_clean)} of {len(clean_files)} clean modified/dropped (e.g. {list(missing_clean)[:5]})")
        if errors:
            pytest.fail(" | ".join(errors))


def test_filter_on_unlabelled_mixed_corpus():
    clean_samples = [
        "The participant raised their left hand and completed the survey.",
        "Data analysis is important for interpreting the experiment results.",
        "Please review the attached document before tomorrow's meeting.",
        "We collected the measurements and recorded each observation carefully.",
    ]
    evil_suffixes = [
        (" ;" * 24) + ("!" * 18) + ("?" * 12),
        (" :::" * 20) + ("#" * 24) + ("!" * 12),
        (" @@" * 22) + ("$" * 20) + ("?" * 14),
    ]
    with tempfile.TemporaryDirectory(prefix="corpus_", dir="/tmp") as input_dir, \
         tempfile.TemporaryDirectory(prefix="result_", dir="/tmp") as output_dir:
        expected = {}
        for i in range(9):
            name = f"sample_{secrets.token_hex(6)}.txt"
            text = clean_samples[i % len(clean_samples)] + " " + clean_samples[(i + 1) % len(clean_samples)]
            with open(os.path.join(input_dir, name), "w", encoding="utf-8") as f:
                f.write(text)
            expected[name] = text
        for i in range(9):
            name = f"sample_{secrets.token_hex(6)}.txt"
            text = clean_samples[i % len(clean_samples)] + evil_suffixes[i % len(evil_suffixes)]
            with open(os.path.join(input_dir, name), "w", encoding="utf-8") as f:
                f.write(text)

        result = subprocess.run(["python3", FILTER, input_dir, output_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on mixed corpus:\n{result.stderr}"
        assert set(os.listdir(output_dir)) == set(expected), "Mixed-corpus filtering produced the wrong files"
        for name, text in expected.items():
            with open(os.path.join(output_dir, name), "r", encoding="utf-8") as f:
                assert f.read() == text, f"Clean transcript {name} was modified"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
