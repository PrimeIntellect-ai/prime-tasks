#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import subprocess

import pytest

HOME = "/home/user"
VIDEO = "/app/ui_render_test.mp4"
OUTPUT = "/home/user/dominant_frequency.txt"
FLOAT_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def read_frequency():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} not found."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert FLOAT_RE.fullmatch(content), (
        f"Output in {OUTPUT} must contain only one numerical float. Got: '{content}'"
    )
    value = float(content)
    assert math.isfinite(value), f"Output frequency is not finite: {content}"
    return value


def reference_frequency(video_path):
    cmd = [
        "ffmpeg", "-v", "error", "-i", video_path,
        "-vf", "crop=100:100:0:0,format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    frame_size = 100 * 100
    assert len(proc.stdout) >= frame_size * 2
    assert len(proc.stdout) % frame_size == 0
    signal = [
        sum(proc.stdout[i:i + frame_size]) / frame_size
        for i in range(0, len(proc.stdout), frame_size)
    ]
    n = len(signal)
    mean = sum(signal) / n
    centered = [x - mean for x in signal]
    best_bin = max(
        range(1, n // 2 + 1),
        key=lambda k: sum(
            (sum(centered[j] * math.cos(2 * math.pi * k * j / n) for j in range(n))) ** 2
            + (sum(centered[j] * math.sin(2 * math.pi * k * j / n) for j in range(n))) ** 2
            for _ in [0]
        ),
    )
    return best_bin * 60.0 / n


def run_pipeline():
    subprocess.run(
        ["bash", "/home/user/run_pipeline.sh"],
        cwd=HOME,
        env={**os.environ, "HOME": HOME},
        check=True,
        timeout=240,
    )
    return read_frequency()


def make_challenge_video(path, frequency):
    term = f"255*(0.5+0.5*sin(2*PI*{frequency}*T))"
    vf = (
        f"geq=r='if(lt(X,100)*lt(Y,100),{term},0)':"
        f"g='if(lt(X,100)*lt(Y,100),{term},0)':"
        f"b='if(lt(X,100)*lt(Y,100),{term},0)'"
    )
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
            "color=c=black:s=640x480:r=60:d=5", "-vf", vf,
            "-c:v", "libx264", path,
        ],
        check=True,
        timeout=120,
    )


def test_pipeline_scripts_exist():
    """Ensure that the required scripts and environment were created."""
    assert os.path.isdir("/home/user/perf_env"), "Virtual environment /home/user/perf_env is missing."
    assert os.path.isfile("/home/user/perf_env/pyvenv.cfg"), "perf_env is not a Python virtual environment."
    assert os.path.isfile("/home/user/perf_env/bin/python"), "perf_env has no Python interpreter."
    assert os.path.isfile("/home/user/extract_signal.sh"), "Script /home/user/extract_signal.sh is missing."
    assert os.path.isfile("/home/user/fft_analyzer.py"), "Script /home/user/fft_analyzer.py is missing."
    assert os.path.isfile("/home/user/run_pipeline.sh"), "Script /home/user/run_pipeline.sh is missing."

    with open("/home/user/extract_signal.sh", errors="replace") as f:
        extractor = f.read()
    with open("/home/user/run_pipeline.sh", errors="replace") as f:
        runner = f.read()
    assert "ffmpeg" in extractor, "extract_signal.sh does not invoke ffmpeg."
    assert "extract_signal.sh" in runner, "run_pipeline.sh does not invoke extract_signal.sh."
    assert "fft_analyzer.py" in runner, "run_pipeline.sh does not invoke fft_analyzer.py."


def test_dominant_frequency_output():
    """Retain the original assertion on the submitted final output."""
    agent_freq = read_frequency()
    target_freq = 12.0
    tolerance = 0.5
    error = abs(agent_freq - target_freq)
    assert error <= tolerance, (
        f"Failure: Agent frequency {agent_freq} is outside {tolerance} of "
        f"target {target_freq} (error: {error})."
    )


def test_pipeline_executes_and_analyzes_video():
    original_expected = reference_frequency(VIDEO)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    original_result = run_pipeline()
    assert abs(original_result - original_expected) <= 0.5, (
        f"Executed pipeline returned {original_result}, independently measured {original_expected}."
    )

    backup = f"/tmp/ui_render_test.original.{os.getpid()}.mp4"
    shutil.copy2(VIDEO, backup)
    challenge_frequency = secrets.choice(
        [x / 5.0 for x in range(23, 94) if abs(x / 5.0 - 12.0) > 1.0]
    )
    try:
        make_challenge_video(VIDEO, challenge_frequency)
        challenge_expected = reference_frequency(VIDEO)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        challenge_result = run_pipeline()
        assert abs(challenge_result - challenge_expected) <= 0.5, (
            f"Pipeline returned {challenge_result} on a challenge video; "
            f"independent analysis found {challenge_expected}."
        )
    finally:
        shutil.move(backup, VIDEO)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        restored_result = run_pipeline()
        assert abs(restored_result - original_expected) <= 0.5
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
