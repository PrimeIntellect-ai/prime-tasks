#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pathlib
import re
import secrets
import subprocess
import tempfile

import pytest

DETECTOR_PATH = "/home/user/detector"
DETECTOR_SOURCE = "/home/user/detector.cpp"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
PROCESSOR_DIR = "/home/user/src"
PROCESSOR_PATH = "/home/user/src/video_processor"
PROCESSOR_SOURCE = "/home/user/src/video_processor.cpp"
MAKEFILE_PATH = "/home/user/src/Makefile"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=kwargs.pop("timeout", 30), **kwargs)


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Executable not found at {path}"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector executable not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector at {DETECTOR_PATH} is not executable"
    assert_elf_executable(DETECTOR_PATH)


def test_video_processor_build_was_repaired():
    assert os.path.isfile(PROCESSOR_SOURCE), f"Missing {PROCESSOR_SOURCE}"
    assert os.path.isfile(MAKEFILE_PATH), f"Missing {MAKEFILE_PATH}"

    source = pathlib.Path(PROCESSOR_SOURCE).read_text(errors="replace")
    makefile = pathlib.Path(MAKEFILE_PATH).read_text(errors="replace")
    assert re.search(r"^\s*#\s*include\s*[<\"]cassert[>\"]", source, re.MULTILINE), \
        "video_processor.cpp is still missing the required <cassert> header"
    assert "-lffmpeg" not in makefile, "Makefile still contains the conflicting -lffmpeg dependency"

    result = run(["make", "-B", "video_processor"], cwd=PROCESSOR_DIR, text=True, timeout=60)
    assert result.returncode == 0, f"video_processor build failed:\n{result.stdout}\n{result.stderr}"
    assert_elf_executable(PROCESSOR_PATH)


def test_adversarial_corpus():
    if not os.path.isfile(DETECTOR_PATH) or not os.access(DETECTOR_PATH, os.X_OK):
        pytest.fail("Detector is missing or not executable; cannot run corpus tests.")

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.mp4"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.mp4"))

    if not evil_files:
        pytest.fail(f"No MP4 files found in evil corpus dir: {EVIL_CORPUS_DIR}")
    if not clean_files:
        pytest.fail(f"No MP4 files found in clean corpus dir: {CLEAN_CORPUS_DIR}")

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        try:
            result = subprocess.run([DETECTOR_PATH, ef], capture_output=True, text=True, timeout=15)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_bypassed.append((os.path.basename(ef), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(ef), f"Error: {e}"))

    for cf in clean_files:
        try:
            result = subprocess.run([DETECTOR_PATH, cf], capture_output=True, text=True, timeout=15)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_modified.append((os.path.basename(cf), output))
        except Exception as e:
            clean_modified.append((os.path.basename(cf), f"Error: {e}"))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: " + ", ".join([f"{f} (Output: {out})" for f, out in evil_bypassed[:5]]) + ("..." if len(evil_bypassed) > 5 else ""))
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected). Offending files: " + ", ".join([f"{f} (Output: {out})" for f, out in clean_modified[:5]]) + ("..." if len(clean_modified) > 5 else ""))
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def encode_rgb_video(path, width, height, frames):
    raw = b"".join(b"".join(bytes(pixel) for pixel in frame) for frame in frames)
    expected_size = width * height * 3 * len(frames)
    assert len(raw) == expected_size
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24",
        "-video_size", f"{width}x{height}", "-framerate", "2", "-i", "pipe:0",
        "-an", "-c:v", "libx264rgb", "-crf", "0", "-preset", "ultrafast",
        "-pix_fmt", "rgb24", str(path),
    ]
    result = subprocess.run(cmd, input=raw, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def solid_frame(width, height, color):
    return [color] * (width * height)


@pytest.fixture(scope="session")
def generated_cases():
    root = pathlib.Path(tempfile.mkdtemp(prefix="vp_cases_"))
    cases = []

    def add(width, height, frames, expected):
        path = root / f"{secrets.token_hex(12)}.mp4"
        encode_rgb_video(path, width, height, frames)
        cases.append((str(path.resolve()), expected))

    add(16, 12, [solid_frame(16, 12, (0, 255, 0))], "REJECT")
    add(20, 14, [solid_frame(20, 14, (0, 1, 0)), solid_frame(20, 14, (0, 200, 0))], "REJECT")
    add(24, 16, [solid_frame(24, 16, (255, 0, 0)), solid_frame(24, 16, (0, 255, 0)), solid_frame(24, 16, (0, 0, 255))], "REJECT")

    add(16, 12, [solid_frame(16, 12, (255, 0, 0))], "ACCEPT")
    add(20, 14, [solid_frame(20, 14, (0, 0, 255))], "ACCEPT")
    add(24, 16, [solid_frame(24, 16, (0, 0, 0))], "ACCEPT")
    add(16, 12, [solid_frame(16, 12, (0, 255, 255))], "ACCEPT")

    almost_green = solid_frame(20, 14, (0, 255, 0))
    almost_green[secrets.randbelow(len(almost_green))] = (1, 255, 0)
    add(20, 14, [almost_green], "ACCEPT")

    add(24, 16, [solid_frame(24, 16, (0, 0, 0)), solid_frame(24, 16, (255, 0, 0))], "ACCEPT")
    return cases


@pytest.fixture(scope="session")
def rebuilt_detector():
    assert os.path.isfile(DETECTOR_SOURCE), f"C++ detector source not found at {DETECTOR_SOURCE}"
    out = os.path.join(tempfile.mkdtemp(prefix="rebuilt_detector_"), "detector")
    result = run([
        "g++", "-std=c++17", "-O2", DETECTOR_SOURCE, "-o", out,
        "-lavformat", "-lavcodec", "-lavutil", "-lswscale",
    ], text=True, timeout=60)
    assert result.returncode == 0, f"detector.cpp does not compile as C++:\n{result.stdout}\n{result.stderr}"
    assert_elf_executable(out)
    return out


def assert_exact_result(executable, path, expected):
    result = subprocess.run([executable, path], capture_output=True, timeout=15)
    assert result.returncode == 0, f"{executable} exited {result.returncode} for {path}; stderr={result.stderr!r}"
    allowed = {expected.encode(), expected.encode() + b"\n"}
    assert result.stdout in allowed, f"Expected exact {expected!r} for {path}, got {result.stdout!r}"


@pytest.mark.parametrize("which", ["submitted", "rebuilt"])
def test_detector_analyzes_randomly_named_generated_videos(which, generated_cases, rebuilt_detector):
    executable = DETECTOR_PATH if which == "submitted" else rebuilt_detector
    for path, expected in generated_cases:
        assert_exact_result(executable, path, expected)


@pytest.mark.parametrize("which", ["submitted", "rebuilt"])
def test_detector_requires_exactly_one_argument(which, generated_cases, rebuilt_detector):
    executable = DETECTOR_PATH if which == "submitted" else rebuilt_detector
    first = generated_cases[0][0]
    second = generated_cases[-1][0]

    no_args = subprocess.run([executable], capture_output=True, timeout=10)
    assert no_args.returncode != 0, "Detector must reject invocation with no video argument"

    two_args = subprocess.run([executable, first, second], capture_output=True, timeout=10)
    assert two_args.returncode != 0, "Detector must reject invocation with more than one video argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
