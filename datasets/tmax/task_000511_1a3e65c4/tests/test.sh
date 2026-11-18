#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE_PATH = "/home/user/filter_corpus"
SOURCE_PATH = "/home/user/filter_corpus.c"
VIDEO_PATH = "/app/sim_video.mp4"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_filter(executable, filepath):
    return subprocess.run(
        [executable, filepath], capture_output=True, timeout=5
    ).returncode


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter_corpus must be a compiled native executable"


def test_source_exists_and_compiles(tmp_path):
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    rebuilt = tmp_path / "filter_corpus_rebuilt"
    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", str(rebuilt), "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"C source failed to compile: {result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus directory {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were rejected (should be accepted). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing at {EVIL_CORPUS_DIR}")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus directory {EVIL_CORPUS_DIR}"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the filter (should be rejected). Offending files: {', '.join(failed_files)}")


def count_white_frames():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", VIDEO_PATH],
        capture_output=True, text=True, timeout=20, check=True,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, timeout=30, check=True,
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0
    count = 0
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        if sum(frame) / len(frame) > 250:
            count += 1
    return count


def atom_line(serial, atom, resid, x, y, z):
    return f"ATOM  {serial:5d} {atom:^4s} ALA A{resid:4d}    {x:8.3f}{y:8.3f}{z:8.3f}\n"


def write_case(path, coords=None, extra_lines=None):
    with open(path, "w") as f:
        if extra_lines:
            f.writelines(extra_lines)
        if coords is not None:
            for i, (x, y, z) in enumerate(coords, 1):
                f.write(atom_line(i, "CA", i, x, y, z))


def test_generated_hidden_cases(tmp_path):
    white_frames = count_white_frames()
    upper = white_frames + 0.5
    assert upper > 2.5, "Video-derived interval contains no valid distances"

    rebuilt = tmp_path / ("rebuilt_" + secrets.token_hex(6))
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", str(rebuilt), "-lm"],
        capture_output=True, text=True, timeout=20,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    cases_dir = tmp_path / ("inputs_" + secrets.token_hex(8))
    cases_dir.mkdir()
    cases = []

    def add(coords, expected, extra=None):
        path = cases_dir / (secrets.token_hex(12) + ".pdb")
        write_case(path, coords, extra)
        cases.append((str(path), expected))

    middle = (2.5 + upper) / 2.0
    add([(0, 0, 0)], True)
    add([(0, 0, 0), (middle, 0, 0), (2 * middle, 0, 0)], True)
    diag_component = middle / math.sqrt(3)
    add([(-4, 1, 2), (-4 + diag_component, 1 + diag_component, 2 + diag_component)], True)
    add([(0, 0, 0), (2.5, 0, 0)], False)
    add([(0, 0, 0), (2.4, 0, 0)], False)
    add([(0, 0, 0), (upper, 0, 0)], False)
    add([(0, 0, 0), (upper + 0.4, 0, 0)], False)
    add(None, False, [atom_line(1, "N", 1, 0, 0, 0)])

    malformed = cases_dir / (secrets.token_hex(12) + ".pdb")
    with open(malformed, "w") as f:
        line = atom_line(1, "CA", 1, 0, 0, 0)
        f.write(line[:30] + " NOTNUM " + line[38:])
    cases.append((str(malformed), False))

    # Non-CA records must not alter which CA atoms are consecutive.
    add(
        [(0, 0, 0), (middle, 0, 0)],
        True,
        [atom_line(90, "N", 1, 100, 100, 100), atom_line(91, "C", 1, -100, -100, -100)],
    )

    rng = random.SystemRandom()
    for _ in range(24):
        should_pass = bool(rng.getrandbits(1))
        points = [(rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(-20, 20))]
        count = rng.randint(2, 7)
        bad_index = rng.randrange(1, count) if not should_pass else -1
        for i in range(1, count):
            if i == bad_index:
                distance = rng.choice([rng.uniform(0.4, 2.2), upper + rng.uniform(0.3, 2.0)])
            else:
                distance = rng.uniform(2.8, upper - 0.25)
            theta = rng.uniform(0, 2 * math.pi)
            phi = rng.uniform(-math.pi / 2, math.pi / 2)
            dx = distance * math.cos(phi) * math.cos(theta)
            dy = distance * math.cos(phi) * math.sin(theta)
            dz = distance * math.sin(phi)
            x, y, z = points[-1]
            points.append((x + dx, y + dy, z + dz))
        add(points, should_pass)

    rng.shuffle(cases)
    failures = []
    for executable in (EXECUTABLE_PATH, str(rebuilt)):
        for path, expected_clean in cases:
            actual_clean = run_filter(executable, path) == 0
            if actual_clean != expected_clean:
                failures.append(
                    f"{os.path.basename(executable)} misclassified {os.path.basename(path)} "
                    f"(expected {'clean' if expected_clean else 'evil'})"
                )
    assert not failures, "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
