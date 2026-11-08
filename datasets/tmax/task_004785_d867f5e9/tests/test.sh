#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest


def get_max_frame(video_path: str) -> int:
    """Computes the 1-indexed frame number with the maximum average grayscale intensity."""
    cmd_probe = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=s=x:p=0", video_path
    ]
    dim_output = subprocess.check_output(cmd_probe).decode().strip()
    w, h = map(int, dim_output.split('x'))
    frame_size = w * h

    cmd_ffmpeg = [
        "ffmpeg", "-i", video_path, "-f", "image2pipe",
        "-pix_fmt", "gray", "-vcodec", "rawvideo", "-"
    ]
    proc = subprocess.Popen(cmd_ffmpeg, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    raw_video, _ = proc.communicate()

    max_avg = -1.0
    max_frame = -1
    num_frames = len(raw_video) // frame_size

    for i in range(num_frames):
        frame_data = raw_video[i * frame_size : (i + 1) * frame_size]
        avg = sum(frame_data) / frame_size
        if avg > max_avg:
            max_avg = avg
            max_frame = i + 1

    return max_frame


def test_video_max_frame():
    video_path = "/app/electrophoresis.mp4"
    result_path = "/home/user/max_frame.txt"

    assert os.path.exists(result_path), f"Result file {result_path} is missing."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), f"File {result_path} does not contain a valid integer."
    student_frame = int(content)

    expected_frame = get_max_frame(video_path)
    assert student_frame == expected_frame, f"Expected max frame {expected_frame}, but got {student_frame}."


def test_sanitizer_clean_corpus():
    script = "/home/user/sanitizer.sh"
    clean_dir = "/app/corpus/clean/"

    assert os.path.exists(script), f"Sanitizer script {script} is missing."
    assert os.path.exists(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(files) > 0, "Clean corpus is empty."

    failed_files = []
    for f in files:
        filepath = os.path.join(clean_dir, f)
        res = subprocess.run(["bash", script, filepath], capture_output=True)
        if res.returncode != 0:
            failed_files.append(f)

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(files)} clean modified/rejected. Offending files: {', '.join(failed_files)}"


def test_sanitizer_evil_corpus():
    script = "/home/user/sanitizer.sh"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(script), f"Sanitizer script {script} is missing."
    assert os.path.exists(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(files) > 0, "Evil corpus is empty."

    failed_files = []
    for f in files:
        filepath = os.path.join(evil_dir, f)
        res = subprocess.run(["bash", script, filepath], capture_output=True)
        if res.returncode == 0:
            failed_files.append(f)

    assert len(failed_files) == 0, f"{len(failed_files)} of {len(files)} evil bypassed. Offending files: {', '.join(failed_files)}"


def format_units(units: int) -> str:
    return f"{units // 10000}.{units % 10000:04d}"


def test_sanitizer_on_generated_opaque_paths():
    script = "/home/user/sanitizer.sh"
    assert os.path.exists(script), f"Sanitizer script {script} is missing."
    assert os.path.isfile(script), f"Sanitizer script {script} is not a regular file."

    case_dir = tempfile.mkdtemp(prefix="sanitizer_cases_", dir="/tmp")
    cases = []
    try:
        # Correct and incorrect files are paired with identical value bodies and
        # placed under opaque names in one directory, so path classification
        # cannot reveal the expected result.
        for _ in range(10):
            units = [secrets.randbelow(99900) + 100 for _ in range(15)]
            total = sum(units)
            body_units = units[:]
            random.SystemRandom().shuffle(body_units)
            body = "".join(format_units(value) + "\n" for value in body_units)

            valid_path = os.path.join(case_dir, secrets.token_hex(16) + ".dat")
            with open(valid_path, "w") as f:
                f.write(f"# SUM: {format_units(total)}\n{body}")
            cases.append((valid_path, 0))

            delta = secrets.choice((-1, 1))
            invalid_path = os.path.join(case_dir, secrets.token_hex(16) + ".dat")
            with open(invalid_path, "w") as f:
                f.write(f"# SUM: {format_units(total + delta)}\n{body}")
            cases.append((invalid_path, 1))

        malformed_contents = [
            "# SUM: 3.0000\n1.0000\nnot-a-number\n2.0000\n",
            "# SUM: 3.0000\n1.0000 2.0000\n",
            "SUM: 3.0000\n1.0000\n2.0000\n",
            "# SUM: 1.0000\n# SUM: 1.0000\n1.0000\n",
        ]
        for content in malformed_contents:
            path = os.path.join(case_dir, secrets.token_hex(16) + ".dat")
            with open(path, "w") as f:
                f.write(content)
            cases.append((path, 1))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            result = subprocess.run(
                ["bash", script, path], capture_output=True, timeout=5
            )
            actual = 0 if result.returncode == 0 else 1
            if actual != expected:
                failures.append(os.path.basename(path))

        assert not failures, "Sanitizer misclassified generated traces: " + ", ".join(failures)
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
