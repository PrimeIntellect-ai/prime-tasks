#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import subprocess
import csv
import hashlib
import random
import secrets
import tempfile
import pytest


def run_filter(script_path, image_path):
    return subprocess.run(
        ["bash", script_path, image_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_filter_script_adversarial_corpus():
    """Retain the original corpus checks."""
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), "Filter script /home/user/filter.sh is missing."

    evil_corpus_path = "/app/corpora/eval_evil"
    clean_corpus_path = "/app/corpora/eval_clean"

    if not os.path.isdir(evil_corpus_path):
        evil_corpus_path = "/app/corpora/evil"
    if not os.path.isdir(clean_corpus_path):
        clean_corpus_path = "/app/corpora/clean"

    evil_files = glob.glob(os.path.join(evil_corpus_path, "*.png"))
    clean_files = glob.glob(os.path.join(clean_corpus_path, "*.png"))

    assert len(evil_files) > 0, f"No evil files found in {evil_corpus_path}"
    assert len(clean_files) > 0, f"No clean files found in {clean_corpus_path}"

    evil_bypassed = []
    for evil_file in evil_files:
        if run_filter(script_path, evil_file) == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        if run_filter(script_path, clean_file) != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified[:5])}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msg)


def test_filter_on_runtime_generated_images():
    """Exercise brightness analysis on unpredictable names and pixel layouts."""
    script_path = "/home/user/filter.sh"
    assert os.path.isfile(script_path), "Filter script /home/user/filter.sh is missing."

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="eval_clean_eval_evil_") as image_dir:
        cases = []

        # Uniformly dark/clean images with randomized dimensions and intensities.
        for should_reject in ([True] * 5 + [False] * 5):
            width = rng.randint(43, 109)
            height = rng.randint(37, 97)
            count = width * height
            if should_reject:
                pixels = [rng.randint(0, 9) for _ in range(count)]
            else:
                pixels = [rng.randint(28, 220) for _ in range(count)]
            cases.append((pixels, width, height, should_reject))

        # Mixed black/white images require using aggregate brightness rather
        # than merely inspecting a particular pixel or the maximum value.
        for should_reject in ([True] * 4 + [False] * 4):
            width = rng.randint(61, 113)
            height = rng.randint(53, 101)
            count = width * height
            target_mean = rng.uniform(0.015, 0.035) if should_reject else rng.uniform(0.09, 0.25)
            white_count = max(1, min(count - 1, round(target_mean * count)))
            pixels = [255] * white_count + [0] * (count - white_count)
            rng.shuffle(pixels)
            actual_mean = sum(pixels) / (255.0 * count)
            assert (actual_mean < 0.05) == should_reject
            cases.append((pixels, width, height, should_reject))

        rng.shuffle(cases)
        failures = []
        for pixels, width, height, should_reject in cases:
            opaque_name = secrets.token_hex(12)
            pgm_path = os.path.join(image_dir, opaque_name + ".pgm")
            png_path = os.path.join(image_dir, opaque_name + ".png")
            with open(pgm_path, "wb") as f:
                f.write(f"P5\n{width} {height}\n255\n".encode("ascii"))
                f.write(bytes(pixels))
            subprocess.run(["convert", pgm_path, png_path], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            os.unlink(pgm_path)

            rc = run_filter(script_path, png_path)
            accepted = rc == 0
            if accepted == should_reject:
                failures.append((os.path.basename(png_path), should_reject, rc))

        assert not failures, f"Runtime-generated brightness cases misclassified: {failures[:5]}"


def _decoded_rgb(path):
    dims = subprocess.run(
        ["identify", "-format", "%w %h", path],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout.strip()
    width, height = map(int, dims.split())
    rgb = subprocess.run(
        ["convert", path, "-alpha", "off", "-colorspace", "sRGB", "-depth", "8", "rgb:-"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    assert len(rgb) == width * height * 3, f"Unexpected decoded size for {path}"
    return width, height, rgb


def _mean_luma(path):
    raw = subprocess.run(
        ["convert", path, "-alpha", "off", "-colorspace", "Gray", "-depth", "8", "gray:-"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    assert raw, f"Could not decode {path}"
    return sum(raw) / (255.0 * len(raw))


def _build_reference_frames(output_dir):
    pattern = os.path.join(output_dir, "frame_%04d.png")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", "/app/rollout.mp4",
         "-vf", "fps=1", pattern],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    return sorted(glob.glob(os.path.join(output_dir, "frame_*.png")))


def test_frames_extraction_and_filtering():
    """Retain named checks and verify survivors against fresh video extraction."""
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), "Frames directory /home/user/frames is missing."

    extracted_frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    assert len(extracted_frames) > 0, "No extracted frames found."
    extracted_basenames = [os.path.basename(f) for f in extracted_frames]

    expected_missing = ["frame_0004.png", "frame_0005.png", "frame_0008.png"]
    for missing in expected_missing:
        assert missing not in extracted_basenames, f"Corrupted frame {missing} was not removed."

    expected_present = [
        "frame_0001.png", "frame_0002.png", "frame_0003.png",
        "frame_0006.png", "frame_0007.png", "frame_0009.png", "frame_0010.png"
    ]
    for present in expected_present:
        assert present in extracted_basenames, f"Clean frame {present} is missing."

    assert extracted_basenames == expected_present, (
        f"Unexpected surviving frame set: {extracted_basenames}"
    )

    with tempfile.TemporaryDirectory(prefix="reference_frames_") as reference_dir:
        reference_files = _build_reference_frames(reference_dir)
        assert len(reference_files) == 10, f"Expected 10 reference frames, got {len(reference_files)}"
        reference_by_name = {os.path.basename(p): p for p in reference_files}
        derived_clean = sorted(
            name for name, path in reference_by_name.items() if _mean_luma(path) >= 0.05
        )
        assert derived_clean == expected_present, (
            f"Fresh extraction produced an unexpected clean-frame set: {derived_clean}"
        )

        for name in expected_present:
            submitted = os.path.join(frames_dir, name)
            with open(submitted, "rb") as f:
                assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{name} is not a PNG file"

            sw, sh, submitted_rgb = _decoded_rgb(submitted)
            rw, rh, reference_rgb = _decoded_rgb(reference_by_name[name])
            assert (sw, sh) == (rw, rh), f"Dimensions of {name} do not match the video frame"

            absolute_error = sum(abs(a - b) for a, b in zip(submitted_rgb, reference_rgb))
            mean_absolute_error = absolute_error / len(reference_rgb)
            assert mean_absolute_error <= 2.0, (
                f"{name} does not match the corresponding frame extracted from rollout.mp4 "
                f"(mean absolute pixel error {mean_absolute_error:.3f})"
            )


def test_valid_rollout_csv():
    """Retain CSV checks and require it to describe exactly the verified survivors."""
    csv_path = "/home/user/valid_rollout.csv"
    assert os.path.isfile(csv_path), "Reproducibility log /home/user/valid_rollout.csv is missing."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."
    assert rows[0] == ["filename", "sha256"], "CSV header is incorrect or missing."

    data_rows = rows[1:]
    assert len(data_rows) == 7, f"Expected 7 data rows, but found {len(data_rows)}."
    assert all(len(row) == 2 for row in data_rows), "Each CSV data row must contain exactly two fields."

    filenames = [row[0] for row in data_rows]
    assert filenames == sorted(filenames), "CSV rows are not sorted alphabetically by filename."
    expected_filenames = [
        "frame_0001.png", "frame_0002.png", "frame_0003.png",
        "frame_0006.png", "frame_0007.png", "frame_0009.png", "frame_0010.png"
    ]
    assert filenames == expected_filenames, "CSV does not list exactly the surviving frames."

    for row in data_rows:
        filename, csv_hash = row
        assert len(csv_hash) == 64, f"Invalid SHA-256 hash length for {filename}."
        assert all(c in "0123456789abcdef" for c in csv_hash), f"Invalid SHA-256 value for {filename}."

        file_path = os.path.join("/home/user/frames", filename)
        assert os.path.isfile(file_path), f"File {filename} listed in CSV but not found in /home/user/frames."

        with open(file_path, "rb") as img_f:
            actual_hash = hashlib.sha256(img_f.read()).hexdigest()

        assert csv_hash == actual_hash, f"Hash mismatch for {filename}. Expected {actual_hash}, got {csv_hash}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
