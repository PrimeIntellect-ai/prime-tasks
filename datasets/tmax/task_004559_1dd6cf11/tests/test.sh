#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest


def read_p5(path):
    data = Path(path).read_bytes()
    pos = 0

    def token():
        nonlocal pos
        while True:
            while pos < len(data) and data[pos] in b" \t\r\n\v\f":
                pos += 1
            if pos < len(data) and data[pos] == ord('#'):
                while pos < len(data) and data[pos] not in b"\r\n":
                    pos += 1
                continue
            break
        start = pos
        while pos < len(data) and data[pos] not in b" \t\r\n\v\f#":
            pos += 1
        assert pos > start, f"Malformed PGM header in {path}"
        return data[start:pos]

    assert token() == b"P5", f"{path} is not a raw P5 PGM"
    width = int(token())
    height = int(token())
    maxval = int(token())
    assert width > 0 and height > 0 and 0 < maxval <= 65535
    assert pos < len(data) and data[pos] in b" \t\r\n\v\f", f"Missing PGM header separator in {path}"
    if data[pos:pos + 2] == b"\r\n":
        pos += 2
    else:
        pos += 1

    bytes_per_sample = 1 if maxval < 256 else 2
    expected_size = width * height * bytes_per_sample
    pixels = data[pos:]
    assert len(pixels) == expected_size, f"Incorrect pixel-data size in {path}"

    if bytes_per_sample == 1:
        values = list(pixels)
    else:
        values = [(pixels[i] << 8) | pixels[i + 1] for i in range(0, len(pixels), 2)]
    return width, height, maxval, pixels, sum(values) // (width * height)


def natural_key(path):
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", path.name)]


def reference_video_frames(tmpdir):
    pattern = os.path.join(tmpdir, "reference_%08d.pgm")
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", "/app/experiment_run.mp4", pattern],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    paths = sorted(Path(tmpdir).glob("reference_*.pgm"), key=natural_key)
    assert paths, "Reference extraction produced no frames"
    return [read_p5(path) for path in paths]


def test_frame_analyzer_source_compiles_and_extracted_pgms_match_video():
    source = Path("/home/user/frame_analyzer.c")
    assert source.is_file(), "Frame analyzer source is missing"
    assert stat.S_ISREG(source.stat().st_mode), "Frame analyzer source is not a regular file"

    with tempfile.TemporaryDirectory() as td:
        analyzer = os.path.join(td, "frame_analyzer")
        built = subprocess.run(
            ["gcc", "-std=c11", "-O2", str(source), "-o", analyzer],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert built.returncode == 0, "frame_analyzer.c does not compile:\n" + built.stderr.decode(errors="replace")
        assert os.path.isfile(analyzer) and os.access(analyzer, os.X_OK)

        reference = reference_video_frames(td)

    pgms_by_directory = {}
    for path in Path("/home/user").rglob("*.pgm"):
        if path.is_file():
            pgms_by_directory.setdefault(path.parent, []).append(path)

    matching_directory = None
    diagnostics = []
    for directory, paths in pgms_by_directory.items():
        paths = sorted(paths, key=natural_key)
        if len(paths) != len(reference):
            continue
        try:
            actual = [read_p5(path) for path in paths]
        except (AssertionError, ValueError) as exc:
            diagnostics.append(f"{directory}: {exc}")
            continue
        if all(a[:4] == e[:4] for a, e in zip(actual, reference)):
            matching_directory = directory
            break

    assert matching_directory is not None, (
        "No directory under /home/user contains all chronologically ordered raw P5 frames "
        "matching an independent ffmpeg extraction. " + "; ".join(diagnostics)
    )


def test_video_metrics_csv():
    csv_path = "/home/user/video_metrics.csv"
    assert os.path.isfile(csv_path), f"Video metrics CSV is missing at {csv_path}"

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 6, f"Expected at least a header and 5 rows, got {len(rows)} rows"

    header = rows[0]
    assert header == ["frame_number", "avg_intensity"], f"Incorrect CSV header: {header}"

    expected_intensities = [255, 0, 128, 64, 192]

    for i, expected in enumerate(expected_intensities):
        try:
            frame_num = int(rows[i+1][0])
            intensity = int(rows[i+1][1])
        except ValueError:
            pytest.fail(f"Row {i+2} contains non-integer values: {rows[i+1]}")

        assert frame_num == i + 1, f"Expected frame_number {i+1}, got {frame_num}"
        diff = abs(intensity - expected)
        assert diff <= 30, f"Frame {i+1} intensity {intensity} is too far from expected {expected} (diff: {diff})"

    with tempfile.TemporaryDirectory() as td:
        reference = reference_video_frames(td)
    exact_expected = [frame[4] for frame in reference]

    assert len(rows) == len(exact_expected) + 1, (
        f"Expected exactly {len(exact_expected)} frame rows, got {len(rows) - 1}"
    )
    for index, expected in enumerate(exact_expected, 1):
        row = rows[index]
        assert len(row) == 2, f"Row {index + 1} must contain exactly two columns: {row}"
        try:
            frame_number = int(row[0])
            intensity = int(row[1])
        except ValueError:
            pytest.fail(f"Row {index + 1} contains non-integer values: {row}")
        assert frame_number == index
        assert intensity == expected, (
            f"Frame {index} has average {intensity}; independently computed exact average is {expected}"
        )


def run_validator(binary, path, *extra):
    return subprocess.run(
        [binary, str(path), *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def test_meta_validator_adversarial_corpus():
    validator_bin = "/home/user/meta_validator"
    assert os.path.isfile(validator_bin), f"Validator binary missing at {validator_bin}"
    assert os.access(validator_bin, os.X_OK), f"Validator binary is not executable"

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_modified = []
    evil_bypassed = []

    for cf in clean_files:
        result = subprocess.run([validator_bin, cf], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([validator_bin, ef], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_meta_validator_generated_suite():
    binary = "/home/user/meta_validator"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    allowed_batches = [8, 16, 32, 64, 128, 256]
    valid_cases = []
    for i in range(48):
        numerator = secrets.randbelow(999999) + 1
        lr = "1.0" if i == 0 else f"{numerator / 1000000:.6f}"
        batch = secrets.choice(allowed_batches)
        folds = secrets.randbelow(9) + 2
        entries = [
            f"learning_rate={lr}",
            f"batch_size={batch}",
            f"cv_folds={folds}",
        ]
        shift = secrets.randbelow(3)
        entries = entries[shift:] + entries[:shift]
        valid_cases.append("\n".join(entries) + "\n")

    invalid_cases = [
        "batch_size=32\ncv_folds=5\n",
        "learning_rate=0.2\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=32\n",
        "learning_rate=0\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=-0.01\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=1.000001\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=nan\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=inf\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=0.2junk\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=\nbatch_size=32\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=7\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=512\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=32.0\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=32x\ncv_folds=5\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=1\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=11\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5.0\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5x\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5\noptimizer=adam\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5\nlearning_rate=0.3\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5\nbatch_size=64\n",
        "learning_rate=0.2\nbatch_size=32\ncv_folds=5\nnot_a_pair\n",
        "",
    ]

    with tempfile.TemporaryDirectory(prefix="schema_" + secrets.token_hex(8) + "_") as td:
        mixed = [(True, text) for text in valid_cases] + [(False, text) for text in invalid_cases]
        # Randomized names and a mixed valid/invalid directory prevent path-based classification.
        for expected_valid, text in mixed:
            path = Path(td) / (secrets.token_hex(16) + ".dat")
            path.write_text(text, encoding="utf-8")
            code = run_validator(binary, path)
            if expected_valid:
                assert code == 0, f"Validator rejected generated valid configuration {text!r}"
            else:
                assert code != 0, f"Validator accepted generated invalid configuration {text!r}"

        missing = Path(td) / (secrets.token_hex(16) + ".missing")
        assert run_validator(binary, missing) != 0, "Validator accepted a nonexistent file"
        assert subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5).returncode != 0
        valid_path = Path(td) / (secrets.token_hex(16) + ".dat")
        valid_path.write_text(valid_cases[0], encoding="utf-8")
        assert run_validator(binary, valid_path, secrets.token_hex(8)) != 0, "Validator accepted extra arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
