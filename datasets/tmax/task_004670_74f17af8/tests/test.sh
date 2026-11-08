#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import uuid

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/detect_corruption.py"
JSON_PATH = "/home/user/corrupted_frames.json"
CLEAN_CORPUS_DIR = "/verifier/eval_corpus/clean/"
EVIL_CORPUS_DIR = "/verifier/eval_corpus/evil/"
VIDEO_PATH = "/app/experiment_record.mp4"
EXPECTED_CORRUPTED_FRAMES = [14, 15, 16, 55, 92, 110, 111, 148]


def clean_env():
    return {
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "HOME": "/home/user",
        "LANG": "C.UTF-8",
    }


def run_detector(path):
    return subprocess.run(
        [sys.executable, SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=clean_env(),
        timeout=20,
    )


def load_json_output():
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_script_uses_numpy_linear_algebra():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"Detector is not valid Python: {exc}")

    imports_numpy = False
    numerical_calls = set()
    allowed_calls = {
        "var", "variance", "std", "svd", "matrix_rank", "eig", "eigvals",
        "eigvalsh", "norm", "det", "cond", "qr"
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports_numpy |= any(alias.name == "numpy" for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imports_numpy |= node.module == "numpy" or (node.module or "").startswith("numpy.")
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                numerical_calls.add(func.id)
            elif isinstance(func, ast.Attribute):
                numerical_calls.add(func.attr)

    assert imports_numpy, "Detector must use numpy for structural numerical analysis."
    assert numerical_calls & allowed_calls, (
        "Detector must contain a matrix rank, SVD, variance, or comparable "
        "numpy linear-algebra/numerical operation."
    )


def test_json_output_exists_and_correct():
    assert os.path.isfile(JSON_PATH), f"JSON output file {JSON_PATH} does not exist."
    data = load_json_output()
    assert isinstance(data, list), f"JSON output must be a list, got {type(data)}."
    assert data == EXPECTED_CORRUPTED_FRAMES, (
        f"Corrupted frames list incorrect. Expected {EXPECTED_CORRUPTED_FRAMES}, got {data}."
    )
    assert all(type(value) is int for value in data), "All frame indices must be integers."


def test_detector_on_opaque_mixed_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} not found."
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} not found."

    clean_files = [
        os.path.join(CLEAN_CORPUS_DIR, name)
        for name in os.listdir(CLEAN_CORPUS_DIR)
        if name.lower().endswith(".png")
    ]
    evil_files = [
        os.path.join(EVIL_CORPUS_DIR, name)
        for name in os.listdir(EVIL_CORPUS_DIR)
        if name.lower().endswith(".png")
    ]
    assert clean_files, f"No PNG files found in {CLEAN_CORPUS_DIR}."
    assert evil_files, f"No PNG files found in {EVIL_CORPUS_DIR}."

    stage = tempfile.mkdtemp(prefix="detector_inputs_")
    cases = []
    try:
        for expected, files in ((0, clean_files), (1, evil_files)):
            for source in files:
                target = os.path.join(stage, uuid.uuid4().hex + ".png")
                shutil.copyfile(source, target)
                cases.append((target, expected))

        # Do not leave the hidden labels or original class-bearing paths available
        # to the submitted process while it is being evaluated.
        shutil.rmtree(CLEAN_CORPUS_DIR)
        shutil.rmtree(EVIL_CORPUS_DIR)
        random.SystemRandom().shuffle(cases)

        failures = []
        for image_path, expected in cases:
            result = run_detector(image_path)
            if result.returncode != expected:
                failures.append((os.path.basename(image_path), expected, result.returncode))
        assert not failures, f"Detector misclassified opaque hidden images: {failures}"

        no_arg = subprocess.run(
            [sys.executable, SCRIPT_PATH], capture_output=True, env=clean_env(), timeout=20
        )
        two_args = subprocess.run(
            [sys.executable, SCRIPT_PATH, cases[0][0], cases[1][0]],
            capture_output=True, env=clean_env(), timeout=20
        )
        assert no_arg.returncode != 0, "Detector must reject invocation without an image argument."
        assert two_args.returncode != 0, "Detector must take exactly one image argument."
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def test_video_frames_and_json_are_consistent_with_content():
    assert os.path.isfile(VIDEO_PATH), f"Video artifact {VIDEO_PATH} does not exist."

    extraction_dir = tempfile.mkdtemp(prefix="video_decode_")
    opaque_dir = tempfile.mkdtemp(prefix="video_inputs_")
    try:
        pattern = os.path.join(extraction_dir, "frame_%09d.png")
        result = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", VIDEO_PATH, "-vsync", "0", pattern,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, f"ffmpeg frame extraction failed: {result.stderr.decode(errors='replace')}"

        extracted = sorted(
            os.path.join(extraction_dir, name)
            for name in os.listdir(extraction_dir)
            if name.endswith(".png")
        )
        assert extracted, "ffmpeg extracted no video frames."

        cases = []
        derived_corrupted = []
        for index, source in enumerate(extracted):
            image = cv2.imread(source, cv2.IMREAD_GRAYSCALE)
            assert image is not None, f"Could not decode extracted frame {index}."

            # The supplied distribution separates solid/blank frames from plots by
            # their matrix variance. This derives labels from frame pixels rather
            # than from filenames or a stored index list.
            variance = float(np.var(image.astype(np.float32)))
            expected_exit = 1 if variance < 4.0 else 0
            if expected_exit == 1:
                derived_corrupted.append(index)

            opaque_path = os.path.join(opaque_dir, uuid.uuid4().hex + ".png")
            shutil.copyfile(source, opaque_path)
            cases.append((opaque_path, expected_exit, index))

        # Remove sequential filenames before invoking the submission.
        shutil.rmtree(extraction_dir)
        extraction_dir = None
        random.SystemRandom().shuffle(cases)

        assert derived_corrupted == EXPECTED_CORRUPTED_FRAMES, (
            f"Content-derived video labels differ from the expected artifact labels: {derived_corrupted}"
        )

        failures = []
        for opaque_path, expected_exit, index in cases:
            detector_result = run_detector(opaque_path)
            if detector_result.returncode != expected_exit:
                failures.append((index, expected_exit, detector_result.returncode))
        assert not failures, f"Detector misclassified extracted video frames: {failures}"

        data = load_json_output()
        assert data == derived_corrupted, (
            f"JSON output does not match corruption indices derived from all video frames: {data}"
        )
    finally:
        if extraction_dir is not None:
            shutil.rmtree(extraction_dir, ignore_errors=True)
        shutil.rmtree(opaque_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
