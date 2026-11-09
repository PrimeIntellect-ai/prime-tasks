#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import cv2
import numpy as np

SCRIPT = Path("/home/user/analyze_audit.sh")
SOURCE = Path("/home/user/detector.cpp")
DETECTOR = Path("/home/user/detector")
OUTPUT = Path("/home/user/peak_frame.txt")
VIDEO = Path("/app/vnc_session.mp4")


def run_solution():
    OUTPUT.unlink(missing_ok=True)
    DETECTOR.unlink(missing_ok=True)

    tmp_root = Path(tempfile.mkdtemp(prefix="audit-run-", dir="/tmp"))
    env = os.environ.copy()
    env["TMPDIR"] = str(tmp_root)
    try:
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    assert result.returncode == 0, (
        f"analyze_audit.sh exited with status {result.returncode}. Output:\n"
        f"{result.stdout[-4000:]}"
    )
    assert OUTPUT.exists(), (
        f"Output file {OUTPUT} does not exist. The C++ program may not have run successfully."
    )
    assert DETECTOR.exists(), "The script did not create /home/user/detector."
    assert os.access(DETECTOR, os.X_OK), "The generated detector is not executable."
    with DETECTOR.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated detector is not a compiled native executable."

    content = OUTPUT.read_text().strip()
    try:
        return int(content)
    except ValueError:
        raise AssertionError(
            f"File {OUTPUT} does not contain a valid integer. Found: '{content}'"
        )


def derive_peak_with_ffmpeg(video, workdir):
    pattern = str(Path(workdir) / "%06d.ppm")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(video), pattern],
        check=True,
        timeout=120,
    )
    frame_paths = sorted(Path(workdir).glob("*.ppm"))
    assert len(frame_paths) >= 2, "Reference extraction produced too few frames."

    frames = []
    for path in frame_paths:
        frame = cv2.imread(str(path), cv2.IMREAD_COLOR)
        assert frame is not None, f"Could not read extracted reference frame {path}."
        frames.append(frame.astype(np.int16))

    differences = [
        float(np.abs(frames[i] - frames[i + 1]).mean())
        for i in range(len(frames) - 1)
    ]
    return int(np.argmax(differences))


def make_random_test_video(path):
    frame_count = 28
    peak = secrets.randbelow(14) + 5
    low = np.array([secrets.randbelow(25) for _ in range(3)], dtype=np.uint8)
    high = np.array([230 + secrets.randbelow(26) for _ in range(3)], dtype=np.uint8)

    writer = cv2.VideoWriter(
        str(path), cv2.VideoWriter_fourcc(*"mp4v"), 15, (96, 64)
    )
    assert writer.isOpened(), "Could not create randomized verifier video."
    try:
        for index in range(frame_count):
            color = low if index <= peak else high
            frame = np.empty((64, 96, 3), dtype=np.uint8)
            frame[:] = color
            writer.write(frame)
    finally:
        writer.release()
    return peak


def test_complete_solution():
    # Preserve the original existence assertions.
    assert SCRIPT.exists(), "Required shell script /home/user/analyze_audit.sh does not exist."
    assert SOURCE.exists(), "Required C++ source file /home/user/detector.cpp does not exist."

    syntax = subprocess.run(
        ["bash", "-n", str(SCRIPT)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert syntax.returncode == 0, f"Shell script has invalid syntax:\n{syntax.stdout}"

    script_text = SCRIPT.read_text(errors="replace")
    assert re.search(r"\bffmpeg\b", script_text), "The script does not invoke ffmpeg."
    assert re.search(r"\bwait\b", script_text), "The script does not wait for its background process."
    assert "$!" in script_text, "The script does not capture the background detector PID."
    assert re.search(r"(?<!&)&(?!&)", script_text), "The detector is not launched in the background."

    # Execute against the supplied audit recording and retain the original result assertion.
    predicted_frame = run_solution()
    target_frame = 142
    threshold = 2
    error = abs(predicted_frame - target_frame)
    assert error <= threshold, (
        f"Predicted frame {predicted_frame} is outside the acceptable threshold of {threshold} "
        f"from the target {target_frame}. Absolute error: {error}"
    )

    # Replace the recording temporarily with a randomized case whose answer is derived
    # independently from frames extracted by ffmpeg. This rejects hardcoded peak values.
    backup = Path("/tmp/verifier_vnc_session_backup.mp4")
    shutil.copy2(VIDEO, backup)
    oracle_dir = Path(tempfile.mkdtemp(prefix="audit-oracle-", dir="/tmp"))
    try:
        nominal_peak = make_random_test_video(VIDEO)
        expected_peak = derive_peak_with_ffmpeg(VIDEO, oracle_dir)
        assert expected_peak == nominal_peak, "Randomized video did not encode a unique expected peak."
        randomized_prediction = run_solution()
        assert randomized_prediction == expected_peak, (
            f"On the randomized recording, detector reported frame {randomized_prediction}; "
            f"the independently derived maximum-difference frame is {expected_peak}."
        )
    finally:
        shutil.copy2(backup, VIDEO)
        backup.unlink(missing_ok=True)
        shutil.rmtree(oracle_dir, ignore_errors=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
