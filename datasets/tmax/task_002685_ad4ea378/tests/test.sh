#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"


def run_detector(path, image, timeout=5):
    return subprocess.run([path, image], capture_output=True, timeout=timeout).returncode


def compile_source(output):
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", output],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"detector.c does not compile:\n{result.stderr}"


def write_p5(path, width, height, pixels):
    with open(path, "wb") as f:
        f.write(f"P5\n# verifier-generated image\n{width} {height}\n255\n".encode())
        f.write(bytes(pixels))


def write_p2(path, width, height, pixels):
    with open(path, "w") as f:
        f.write("P2\n# verifier-generated image\n")
        f.write(f"{width} {height}\n255\n")
        for row in range(height):
            start = row * width
            f.write(" ".join(str(v) for v in pixels[start:start + width]) + "\n")


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector executable missing: {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector is not executable: {DETECTOR}"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled native executable"
    assert os.path.isfile(SOURCE), f"C source missing: {SOURCE}"
    with open(SOURCE, "rb") as f:
        source = f.read()
    assert b"\x00" not in source, "detector.c is not a text C source file"
    assert b"main" in source, "detector.c does not contain a main function"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.pgm"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.pgm"))

    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run([DETECTOR, cf], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run([DETECTOR, ef], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected (expected exit code 0): {clean_failures}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed (expected exit code 1): {evil_failures}")

    assert not error_msg, " | ".join(error_msg)


def test_source_build_and_generated_images():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="pgm_detector_check_") as td:
        rebuilt = os.path.join(td, "rebuilt_detector")
        compile_source(rebuilt)

        # Confirm the submitted source, when independently compiled, also passes
        # the supplied corpus rather than merely accompanying an unrelated binary.
        for image in glob.glob("/app/corpus/clean/*.pgm"):
            assert run_detector(rebuilt, image) == 0, f"Compiled detector.c rejects clean corpus image {image}"
        for image in glob.glob("/app/corpus/evil/*.pgm"):
            assert run_detector(rebuilt, image) == 1, f"Compiled detector.c accepts evil corpus image {image}"

        width = rng.randint(53, 79)
        height = rng.randint(47, 71)
        clean = [rng.randint(70, 190) for _ in range(width * height)]

        corrupt = clean.copy()
        x0, x1 = width // 5, 4 * width // 5
        y0, y1 = height // 5, 4 * height // 5
        for y in range(y0, y1):
            for x in range(x0, x1):
                corrupt[y * width + x] = 0

        dark = [rng.randint(1, 8) for _ in range(width * height)]
        probe = os.path.join(td, "same_unpredictable_probe_name.pgm")
        cases = [
            (write_p5, clean, 0, "clean P5"),
            (write_p5, corrupt, 1, "black-patch P5"),
            (write_p5, dark, 1, "dark-outlier P5"),
            (write_p2, clean, 0, "clean P2"),
            (write_p2, corrupt, 1, "black-patch P2"),
        ]

        # Every case overwrites the same randomized pathname, preventing a
        # classifier based only on corpus names or input pathnames from passing.
        for writer, pixels, expected, description in cases:
            writer(probe, width, height, pixels)
            installed_rc = run_detector(DETECTOR, probe)
            rebuilt_rc = run_detector(rebuilt, probe)
            assert installed_rc == expected, f"Installed detector misclassified {description}: exit {installed_rc}"
            assert rebuilt_rc == expected, f"Compiled detector.c misclassified {description}: exit {rebuilt_rc}"


def test_clean_count():
    count_file = "/home/user/clean_count.txt"
    assert os.path.isfile(count_file), f"Count file missing: {count_file}"

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"Count file does not contain a valid integer: '{content}'"
    count = int(content)

    assert count == 45, f"Expected clean count to be 45, but got {count}"


def test_video_frames_are_consistent_with_count():
    with tempfile.TemporaryDirectory(prefix="video_detector_check_") as td:
        pattern = os.path.join(td, "frame_%06d.pgm")
        extraction = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i",
             "/app/droplet_experiment.mp4", "-vf", "fps=1", "-vsync", "0", pattern],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert extraction.returncode == 0, f"Could not extract verification frames: {extraction.stderr}"
        frames = sorted(glob.glob(os.path.join(td, "frame_*.pgm")))
        assert len(frames) == 60, f"Expected 60 frames at fps=1, found {len(frames)}"

        clean = 0
        for frame in frames:
            rc = run_detector(DETECTOR, frame)
            assert rc in (0, 1), f"Detector returned invalid exit code {rc} for extracted frame"
            clean += rc == 0

        with open("/home/user/clean_count.txt") as f:
            recorded = int(f.read().strip())
        assert clean == recorded, f"Recorded count {recorded} does not match detector result {clean} on fps=1 frames"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
