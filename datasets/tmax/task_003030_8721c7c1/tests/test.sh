#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

FILTER_PATH = "/home/user/filter"


def get_actual_video_duration(video_path):
    """Use ffprobe to get the actual duration of the video."""
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        video_path,
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed: {result.stderr}")
    return float(result.stdout.strip())


def test_video_duration_extracted():
    """Check if the video duration was correctly extracted and saved."""
    output_file = "/home/user/video_duration.txt"
    video_file = "/app/test_video.mp4"

    assert os.path.exists(output_file), f"Output file missing: {output_file}"

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content, f"Output file {output_file} is empty."

    try:
        student_duration = float(content)
    except ValueError:
        pytest.fail(f"Content of {output_file} is not a valid number: '{content}'")

    expected_duration = get_actual_video_duration(video_file)
    assert abs(student_duration - expected_duration) < 0.05, \
        f"Duration mismatch. Expected ~{expected_duration}, got {student_duration}"


def test_filter_executable_exists():
    """Check that both the requested C++ source and compiled executable exist."""
    source_path = "/home/user/filter.cpp"
    assert os.path.isfile(source_path), f"C++ source missing at {source_path}"
    assert os.path.isfile(FILTER_PATH), f"Filter executable missing at {FILTER_PATH}"
    assert os.access(FILTER_PATH, os.X_OK), f"Filter at {FILTER_PATH} is not executable"
    with open(FILTER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Filter is not a compiled ELF executable"


def run_filter(filepath, use_valgrind=False):
    cmd = []
    if use_valgrind:
        cmd.extend(["valgrind", "--leak-check=full", "--error-exitcode=255", "--quiet"])
    cmd.extend([FILTER_PATH, filepath])
    try:
        result = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1.0
        )
        return result.returncode, result.stderr.decode("utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return -1, "Timeout (infinite loop)"


def test_adversarial_corpus_filter():
    """Retain the checks against the supplied corpus, including valgrind."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    valgrind_available = subprocess.run(
        ["which", "valgrind"], stdout=subprocess.PIPE
    ).returncode == 0

    clean_files = [
        os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    ]
    evil_files = [
        os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    ]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    evil_failed = []

    for c_file in clean_files:
        code, stderr = run_filter(c_file, valgrind_available)
        if code != 0:
            basename = os.path.basename(c_file)
            reason = "Memory Leak/Crash" if code == 255 else f"Exit code {code}"
            clean_failed.append(f"{basename} ({reason})")

    for e_file in evil_files:
        code, stderr = run_filter(e_file, valgrind_available)
        if code != 1:
            basename = os.path.basename(e_file)
            reason = "Memory Leak/Crash" if code == 255 else f"Exit code {code}"
            evil_failed.append(f"{basename} ({reason})")

    error_messages = []
    if clean_failed:
        error_messages.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failed)
        )
    if evil_failed:
        error_messages.append(
            f"{len(evil_failed)} of {len(evil_files)} evil bypassed/failed: "
            + ", ".join(evil_failed)
        )
    if error_messages:
        pytest.fail("\n".join(error_messages))


def random_text(min_len=3, max_len=24):
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-:"
    return "".join(secrets.choice(alphabet) for _ in range(random.randint(min_len, max_len)))


def make_balanced_log():
    groups = []
    for _ in range(random.randint(1, 4)):
        depth = random.randint(1, 7)
        groups.append("[" * depth + random_text() + "]" * depth)
    return "[INFO] " + random_text() + " ".join(groups) + "\n"


def make_unclosed_log():
    groups = []
    for _ in range(random.randint(1, 4)):
        depth = random.randint(1, 7)
        groups.append("[" * depth + random_text() + "]" * depth)
    target = random.randrange(len(groups))
    # Remove one or more closing brackets, reproducing the malformed syntax in
    # the supplied evil sample while varying depth, text, size, and position.
    remove_count = random.randint(1, min(3, groups[target].count("]")))
    for _ in range(remove_count):
        pos = groups[target].rfind("]")
        groups[target] = groups[target][:pos] + groups[target][pos + 1:]
    return "[INFO] " + random_text() + " ".join(groups) + "\n"


def test_filter_on_runtime_generated_inputs():
    """Exercise content classification at unpredictable, label-neutral paths."""
    cases = []
    for _ in range(10):
        cases.append((make_balanced_log(), 0))
        cases.append((make_unclosed_log(), 1))
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="filter_cases_") as case_dir:
        materialized = []
        for content, expected in cases:
            path = os.path.join(case_dir, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            materialized.append((path, expected))

        random.SystemRandom().shuffle(materialized)
        for path, expected in materialized:
            code, stderr = run_filter(path)
            if code != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected {expected}, got {code}"
                )

    if failures:
        pytest.fail("Runtime-generated classification failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
