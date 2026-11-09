#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import subprocess
from collections import defaultdict

import cv2
import numpy as np

EXECUTABLE = "/home/user/filter"
SOURCE = "/home/user/filter.cpp"
EXPECTED_REJECTED = ["15", "16", "17", "50", "85"]


def run_filter(executable, matrix_path, expected):
    result = subprocess.run(
        [executable, matrix_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Filter failed on {matrix_path}: {result.stderr}"
    assert result.stdout in (expected, expected + "\n"), (
        f"Expected exact output {expected!r} for {matrix_path}, got {result.stdout!r}"
    )


def natural_key(path):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r"(\d+)", os.path.basename(path))]


def load_exported_matrix(path):
    try:
        values = np.loadtxt(path)
    except Exception:
        return None
    if values.size != 4096:
        return None
    values = np.asarray(values, dtype=np.float64).reshape(64, 64)
    if not np.all(np.isfinite(values)) or values.min() < 0.0 or values.max() > 255.0:
        return None
    return values


def independently_extract_video():
    capture = cv2.VideoCapture("/app/fluid_flow.mp4")
    assert capture.isOpened(), "Could not open the supplied video"
    fps = capture.get(cv2.CAP_PROP_FPS)
    assert abs(fps - 10.0) < 0.1, f"Unexpected source frame rate: {fps}"
    frames = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.resize(gray, (64, 64), interpolation=cv2.INTER_AREA)
        frames.append(gray.astype(np.float64))
    capture.release()
    assert len(frames) == 100, f"Expected 100 video frames, decoded {len(frames)}"
    return frames


def find_exported_frames(reference_frames):
    grouped = defaultdict(list)
    for path in glob.glob("/home/user/**/*.txt", recursive=True):
        if os.path.abspath(path) == "/home/user/rejected_frames.txt":
            continue
        matrix = load_exported_matrix(path)
        if matrix is not None:
            grouped[os.path.dirname(path)].append((path, matrix))

    failures = []
    for directory, entries in grouped.items():
        entries.sort(key=lambda item: natural_key(item[0]))
        if len(entries) != 100:
            continue
        acceptable = True
        for i, (_, actual) in enumerate(entries):
            reference = reference_frames[i]
            mae = float(np.mean(np.abs(actual - reference)))
            correlation = float(np.corrcoef(actual.ravel(), reference.ravel())[0, 1])
            if not np.isfinite(correlation) or mae > 35.0 or correlation < 0.85:
                acceptable = False
                failures.append(
                    f"{directory}: frame {i + 1} has MAE={mae:.2f}, correlation={correlation:.3f}"
                )
                break
        if acceptable:
            return entries

    detail = failures[0] if failures else "no directory contained exactly 100 valid 64x64 matrices"
    raise AssertionError(f"Could not find chronological exported matrices matching the video: {detail}")


def test_filter_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled filter must be a native executable"
    assert os.path.isfile(SOURCE), f"C++ source {SOURCE} does not exist."
    with open(SOURCE, "r", errors="ignore") as f:
        source = f.read()
    assert "main" in source, "filter.cpp does not contain a C++ program entry point"


def test_adversarial_corpus_evaluation():
    clean_files = glob.glob("/app/corpus/clean/*.txt")
    evil_files = glob.glob("/app/corpus/evil/*.txt")
    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for path in clean_files:
        try:
            run_filter(EXECUTABLE, path, "ACCEPT")
        except AssertionError:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        try:
            run_filter(EXECUTABLE, path, "REJECT")
        except AssertionError:
            evil_failed.append(os.path.basename(path))

    error_msg = []
    if clean_failed:
        error_msg.append(
            f"{len(clean_failed)} of {len(clean_files)} clean matrices were not accepted: {', '.join(clean_failed)}"
        )
    if evil_failed:
        error_msg.append(
            f"{len(evil_failed)} of {len(evil_files)} evil matrices were not rejected: {', '.join(evil_failed)}"
        )
    assert not clean_failed and not evil_failed, " | ".join(error_msg)


def test_filter_on_unseen_derived_cases(tmp_path):
    rng = np.random.default_rng(secrets.randbits(128))
    cases = []

    for index in range(4):
        q1, _ = np.linalg.qr(rng.normal(size=(64, 64)))
        q2, _ = np.linalg.qr(rng.normal(size=(64, 64)))
        if index < 2:
            singular_values = rng.uniform(1.0, 20.0, 64)
            expected = "ACCEPT"
        else:
            singular_values = rng.uniform(1.0, 20.0, 64)
            singular_values[-1] = 1e-7
            expected = "REJECT"
        matrix = q1 @ np.diag(singular_values) @ q2.T
        cases.append((matrix, expected))

    singular = rng.normal(size=(64, 64))
    singular[-1] = singular[0]
    cases.append((singular, "REJECT"))

    for index, (matrix, expected) in enumerate(cases):
        path = tmp_path / f"unseen_{index}.txt"
        np.savetxt(path, matrix, fmt="%.17g")
        computed = np.linalg.svd(matrix, compute_uv=False)
        if expected == "ACCEPT":
            assert computed[0] / computed[-1] < 10000
        else:
            assert computed[-1] < 1e-5 or computed[0] / max(computed[-1], np.finfo(float).tiny) > 10000
        run_filter(EXECUTABLE, str(path), expected)


def test_video_exports_filtering_and_rejected_log():
    reference_frames = independently_extract_video()
    exported = find_exported_frames(reference_frames)

    rejected_by_filter = []
    for frame_number, (path, _) in enumerate(exported, start=1):
        result = subprocess.run(
            [EXECUTABLE, path], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, f"Filter failed on exported frame {frame_number}"
        assert result.stdout in ("ACCEPT", "ACCEPT\n", "REJECT", "REJECT\n"), (
            f"Invalid output on exported frame {frame_number}: {result.stdout!r}"
        )
        if result.stdout.strip() == "REJECT":
            rejected_by_filter.append(str(frame_number))

    output_file = "/home/user/rejected_frames.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."
    with open(output_file, "r") as f:
        actual_frames = [line.strip() for line in f if line.strip()]

    assert actual_frames == EXPECTED_REJECTED, (
        f"Expected rejected frames {EXPECTED_REJECTED}, but got {actual_frames}."
    )
    assert actual_frames == rejected_by_filter, (
        "rejected_frames.txt does not match actual filter results on the exported frames"
    )


def test_condition_plot_is_valid_and_has_generation_script():
    plot_file = "/home/user/cond_plot.png"
    assert os.path.isfile(plot_file), f"Plot file {plot_file} does not exist."
    with open(plot_file, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "cond_plot.png is not a PNG file"

    image = cv2.imread(plot_file, cv2.IMREAD_UNCHANGED)
    assert image is not None, "cond_plot.png cannot be decoded"
    assert image.shape[0] >= 200 and image.shape[1] >= 300, "Condition plot is implausibly small"
    assert float(np.std(image.astype(np.float64))) > 2.0, "Condition plot is blank or uniform"
    colors = image.reshape(-1, image.shape[2] if image.ndim == 3 else 1)
    assert len(np.unique(colors, axis=0)) > 8, "Condition plot lacks plotted graphical content"

    scripts = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if not (name.endswith(".py") or os.access(path, os.X_OK)):
                continue
            try:
                if os.path.getsize(path) > 2_000_000:
                    continue
                with open(path, "r", errors="ignore") as f:
                    text = f.read().lower()
            except OSError:
                continue
            if (name.endswith(".py") or "python" in text[:200]) and "cond_plot.png" in text:
                scripts.append(text)

    assert scripts, "No Python script that generates cond_plot.png was found"
    assert any(
        "savefig" in text
        and ("condition" in text or "linalg.cond" in text or "svd" in text)
        and ("plot(" in text or ".plot(" in text)
        for text in scripts
    ), "The plotting script does not compute/read condition numbers and create a line plot"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
