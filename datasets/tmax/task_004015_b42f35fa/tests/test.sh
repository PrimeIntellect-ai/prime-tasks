#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest


def image_mean(path):
    result = subprocess.run(
        ["convert", path, "-format", "%[fx:mean]", "info:"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"convert could not read {path}: {result.stderr}"
    return float(result.stdout.strip())


def numeric_key(path):
    matches = re.findall(r"\d+", os.path.basename(path))
    assert matches, f"Frame filename has no frame number: {path}"
    return int(matches[-1])


def image_files(directory):
    found = []
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        result = subprocess.run(["identify", path], capture_output=True, text=True)
        if result.returncode == 0:
            found.append(path)
    return sorted(found, key=numeric_key)


def read_stats(path):
    with open(path, newline="") as handle:
        rows = list(csv.reader(handle))
    assert rows, "Stats file is empty"
    assert rows[0] == ["frame_number", "mean_brightness"], f"Incorrect header: {rows[0]}"
    parsed = []
    for index, row in enumerate(rows[1:], 1):
        assert len(row) == 2, f"Stats row {index} does not have two columns: {row}"
        try:
            parsed.append((int(row[0]), float(row[1])))
        except ValueError:
            pytest.fail(f"Invalid stats row {index}: {row}")
    return parsed


def assert_means_match(stats, expected):
    assert [number for number, _ in stats] == [number for number, _ in expected]
    # Common ImageMagick representations are normalized, percentage, or Q16.
    scales = (1.0, 100.0, 65535.0)
    for scale in scales:
        tolerance = max(1e-5 * scale, 1e-6)
        if all(abs(observed - mean * scale) <= tolerance for (_, observed), (_, mean) in zip(stats, expected)):
            return
    pytest.fail("Mean brightness values do not match brightness recomputed with ImageMagick")


def test_frame_extraction_and_stats():
    frames_dir = "/home/user/frames"
    stats_file = "/home/user/frame_stats.csv"

    assert os.path.exists(frames_dir), f"Frames directory missing at {frames_dir}"
    assert os.path.isdir(frames_dir), f"{frames_dir} is not a directory"
    assert os.path.exists(stats_file), f"Stats file missing at {stats_file}"

    with open(stats_file, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Stats file is empty"
    header = rows[0]
    assert header == ['frame_number', 'mean_brightness'], f"Incorrect header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 50, f"Expected 50 data rows, got {len(data_rows)}"

    frame_numbers = []
    for i, row in enumerate(data_rows):
        try:
            frame_num = int(row[0])
            frame_numbers.append(frame_num)
        except ValueError:
            pytest.fail(f"Invalid frame number at row {i+1}: {row[0]}")
    assert frame_numbers == sorted(frame_numbers), "frame_stats.csv is not sorted by frame number"

    actual_frames = image_files(frames_dir)
    assert len(actual_frames) == 50, f"Expected 50 readable extracted frame images, got {len(actual_frames)}"
    actual_numbers = [numeric_key(path) for path in actual_frames]
    assert len(set(actual_numbers)) == 50, "Extracted frame filenames do not have unique frame numbers"

    with tempfile.TemporaryDirectory() as reference_dir:
        pattern = os.path.join(reference_dir, "frame_%06d.png")
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "/app/video.mp4", "-vf", "fps=10", pattern],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Could not create verification frames: {result.stderr}"
        reference_frames = image_files(reference_dir)
        assert len(reference_frames) == 50

        for actual, reference in zip(actual_frames, reference_frames):
            dimensions = subprocess.run(
                ["identify", "-format", "%wx%h", actual], capture_output=True, text=True
            )
            assert dimensions.returncode == 0
            assert dimensions.stdout == "1280x720", f"Wrong frame dimensions for {actual}: {dimensions.stdout}"

            comparison = subprocess.run(
                ["compare", "-metric", "RMSE", actual, reference, "null:"],
                capture_output=True,
                text=True,
            )
            metric_text = comparison.stderr.strip()
            match = re.search(r"\(([^)]+)\)", metric_text)
            assert match, f"Could not compare extracted frame {actual}: {metric_text}"
            assert float(match.group(1)) < 0.05, f"Extracted frame does not match the video: {actual}"

    stats = read_stats(stats_file)
    expected = [(numeric_key(path), image_mean(path)) for path in actual_frames]
    expected.sort(key=lambda item: item[0])
    assert_means_match(stats, expected)


def test_compute_stats_script_exists_executable_and_computes():
    script = "/home/user/compute_stats.sh"
    frames_dir = "/home/user/frames"
    stats_file = "/home/user/frame_stats.csv"
    assert os.path.isfile(script), f"Script missing at {script}"
    assert os.access(script, os.X_OK), f"Script at {script} is not executable"

    original_frames = frames_dir + ".verifier_backup"
    original_stats = stats_file + ".verifier_backup"
    assert not os.path.exists(original_frames)
    assert not os.path.exists(original_stats)

    existing_images = image_files(frames_dir)
    extension = os.path.splitext(existing_images[0])[1] or ".png"
    os.rename(frames_dir, original_frames)
    os.rename(stats_file, original_stats)
    os.mkdir(frames_dir)
    try:
        specs = [(10, "gray(87)"), (2, "gray(203)"), (1, "gray(31)")]
        expected = []
        for number, color in specs:
            path = os.path.join(frames_dir, f"frame_{number:06d}{extension}")
            made = subprocess.run(
                ["convert", "-size", "19x13", f"xc:{color}", path],
                capture_output=True,
                text=True,
            )
            assert made.returncode == 0, made.stderr
            expected.append((number, image_mean(path)))

        result = subprocess.run([script], capture_output=True, text=True)
        assert result.returncode == 0, f"compute_stats.sh failed: {result.stderr}"
        assert os.path.isfile(stats_file), "compute_stats.sh did not create frame_stats.csv"
        stats = read_stats(stats_file)
        expected.sort(key=lambda item: item[0])
        assert_means_match(stats, expected)
    finally:
        shutil.rmtree(frames_dir, ignore_errors=True)
        if os.path.exists(stats_file):
            os.remove(stats_file)
        os.rename(original_frames, frames_dir)
        os.rename(original_stats, stats_file)


def test_filter_datasets_script_exists_and_executable():
    script_path = "/home/user/filter_datasets.sh"
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_adversarial_corpus_filtering():
    script_path = "/home/user/filter_datasets.sh"
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    result_clean = subprocess.run(["bash", script_path, clean_dir], capture_output=True, text=True)
    assert result_clean.returncode == 0, f"Script failed on clean dir with exit code {result_clean.returncode}"
    clean_output = result_clean.stdout.strip().split('\n') if result_clean.stdout.strip() else []
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    false_positives = [f for f in clean_output if any(cf in f for cf in clean_files)]
    assert len(false_positives) == 0, f"{len(false_positives)} of {len(clean_files)} clean files incorrectly flagged: {false_positives}"

    result_evil = subprocess.run(["bash", script_path, evil_dir], capture_output=True, text=True)
    assert result_evil.returncode == 0, f"Script failed on evil dir with exit code {result_evil.returncode}"
    evil_output = result_evil.stdout.strip()
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    missed_evil = [f for f in evil_files if f not in evil_output]
    assert len(missed_evil) == 0, f"{len(missed_evil)} of {len(evil_files)} evil files bypassed detection: {missed_evil}"


def write_rows(path, rows):
    with open(path, "w", newline="") as handle:
        handle.write("\n".join(rows) + "\n")


def fresh_rows(count):
    return [",".join(secrets.token_hex(8) for _ in range(5)) for _ in range(count)]


def test_filter_datasets_on_unseen_mixed_corpus():
    script = "/home/user/filter_datasets.sh"
    with tempfile.TemporaryDirectory(prefix="corpus_") as directory:
        expected = set()

        clean_name = f"control_{uuid.uuid4().hex}.csv"
        clean_rows = fresh_rows(20)
        write_rows(os.path.join(directory, clean_name), clean_rows)

        same_half_name = f"samehalf_{uuid.uuid4().hex}.csv"
        same_half_rows = fresh_rows(20)
        same_half_rows[7] = same_half_rows[2]
        write_rows(os.path.join(directory, same_half_name), same_half_rows)

        for duplicate_count in (1, 3):
            evil_name = f"leak_{uuid.uuid4().hex}.csv"
            evil_rows = fresh_rows(20)
            for offset in range(duplicate_count):
                evil_rows[13 + offset] = evil_rows[1 + offset]
            write_rows(os.path.join(directory, evil_name), evil_rows)
            expected.add(evil_name)

        with open(os.path.join(directory, "ignored.txt"), "w") as handle:
            handle.write("not a csv\n")

        result = subprocess.run([script, directory], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on generated corpus: {result.stderr}"
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        actual = {os.path.basename(line) for line in lines}
        assert len(lines) == len(actual), f"Duplicate or malformed output lines: {lines}"
        assert actual == expected, f"Expected leaked files {sorted(expected)}, got {sorted(actual)}"


def test_saved_results():
    clean_results_file = "/home/user/clean_results.txt"
    evil_results_file = "/home/user/evil_results.txt"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(clean_results_file), f"Missing {clean_results_file}"
    assert os.path.exists(evil_results_file), f"Missing {evil_results_file}"

    with open(clean_results_file, 'r') as f:
        clean_content = f.read().strip()
    assert clean_content == "", f"clean_results.txt should be empty, but contains: {clean_content}"

    with open(evil_results_file, 'r') as f:
        evil_content = f.read().strip()

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    missed = [f for f in evil_files if f not in evil_content]
    assert len(missed) == 0, f"evil_results.txt is missing evil files: {missed}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
