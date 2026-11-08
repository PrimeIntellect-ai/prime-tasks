#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
import pytest

FRAME_W = 640
FRAME_H = 480
FRAME_SIZE = FRAME_W * FRAME_H
CENTER_X0 = 270
CENTER_X1 = 370
CENTER_Y0 = 190
CENTER_Y1 = 290
CENTER_PIXELS = 100 * 100
FLOAT_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def compute_target_load():
    """Recompute the target directly from the supplied video."""
    video_path = "/app/server_load.mp4"
    if not os.path.exists(video_path):
        return 62.35

    cmd = [
        "ffmpeg", "-i", video_path,
        "-f", "image2pipe",
        "-pix_fmt", "gray",
        "-vcodec", "rawvideo", "-"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    total_sum = 0
    frame_count = 0
    while True:
        raw = proc.stdout.read(FRAME_SIZE)
        if not raw or len(raw) < FRAME_SIZE:
            break
        for y in range(CENTER_Y0, CENTER_Y1):
            start = y * FRAME_W + CENTER_X0
            total_sum += sum(raw[start:start + 100])
        frame_count += 1

    proc.stdout.close()
    proc.wait()
    assert proc.returncode == 0, "ffmpeg failed while computing target load"

    if frame_count == 0:
        return 0.0
    avg_intensity = total_sum / (frame_count * CENTER_PIXELS)
    return (avg_intensity / 255.0) * 100


def parse_single_float(data, description):
    text = data.decode("utf-8", errors="strict").strip()
    assert FLOAT_RE.fullmatch(text), f"{description} did not emit exactly one floating-point number: {text!r}"
    return float(text)


def make_frame():
    frame = bytearray(os.urandom(FRAME_SIZE))
    center_sum = 0
    for y in range(CENTER_Y0, CENTER_Y1):
        row = os.urandom(100)
        start = y * FRAME_W + CENTER_X0
        frame[start:start + 100] = row
        center_sum += sum(row)
    return bytes(frame), center_sum


def analyzer_cases():
    frames = [make_frame() for _ in range(3)]
    raw = b"".join(frame for frame, _ in frames)
    expected = (sum(total for _, total in frames) / (3 * CENTER_PIXELS * 255.0)) * 100

    one_frame, one_sum = make_frame()
    partial = os.urandom(FRAME_SIZE // 3)
    expected_partial = (one_sum / (CENTER_PIXELS * 255.0)) * 100
    return [(raw, expected), (one_frame + partial, expected_partial)]


def exercise_analyzer(path, cases):
    for raw, expected in cases:
        result = subprocess.run(
            [path], input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=15, check=False
        )
        assert result.returncode == 0, f"{path} exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
        actual = parse_single_float(result.stdout, path)
        assert abs(actual - expected) <= 0.02, (
            f"{path} produced {actual}, expected {expected:.6f} for synthetic frames"
        )


def test_timezone_configuration():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"File missing: {bashrc_path}"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert "TZ" in content and "Etc/UTC" in content, "TZ=Etc/UTC not configured properly in /home/user/.bashrc"

    env = os.environ.copy()
    env.pop("TZ", None)
    result = subprocess.run(
        ["bash", "--noprofile", "--rcfile", bashrc_path, "-i", "-c", "printf '%s' \"$TZ\""],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=10, check=False
    )
    assert result.returncode == 0
    assert result.stdout.decode() == "Etc/UTC", "Sourcing .bashrc does not set TZ to Etc/UTC"


def test_analyzer_artifacts_and_behavior():
    source_path = "/home/user/analyzer.c"
    binary_path = "/home/user/analyzer"

    assert os.path.isfile(source_path), f"C source missing: {source_path}"
    assert os.path.isfile(binary_path), f"Analyzer binary missing: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Analyzer is not executable: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Analyzer is not a compiled ELF executable"

    fd, rebuilt_path = tempfile.mkstemp(prefix="rebuilt_analyzer_")
    os.close(fd)
    os.unlink(rebuilt_path)
    compile_result = subprocess.run(
        ["gcc", "-O2", "-std=c11", source_path, "-o", rebuilt_path, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
    )
    assert compile_result.returncode == 0, (
        "analyzer.c does not compile: " + compile_result.stderr.decode(errors="replace")
    )

    cases = analyzer_cases()
    hidden_binary = "/tmp/hidden_analyzer_" + uuid.uuid4().hex
    os.replace(binary_path, hidden_binary)
    try:
        exercise_analyzer(rebuilt_path, cases)
    finally:
        os.replace(hidden_binary, binary_path)
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)

    exercise_analyzer(binary_path, cases)


def test_average_load_metric():
    file_path = "/home/user/average_load.txt"
    assert os.path.exists(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r") as f:
        text = f.read().strip()
    assert FLOAT_RE.fullmatch(text), "/home/user/average_load.txt must contain a single floating-point number"
    try:
        val = float(text)
    except ValueError:
        pytest.fail("Could not parse float from /home/user/average_load.txt")

    target = compute_target_load()
    tolerance = 0.5
    assert abs(val - target) <= tolerance, f"Computed load {val} is not within {tolerance} of the target {target:.2f}"


def test_scheduled_task_setup():
    script_path = "/home/user/monitor.sh"
    cron_path = "/home/user/monitor.cron"

    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    with open(script_path, "r") as f:
        script_content = f.read()
    active_script = "\n".join(
        line for line in script_content.replace("\\\n", " ").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    pipeline_re = re.compile(
        r"(?:^|&&\s*|;\s*)ffmpeg\s+-i\s+/app/server_load\.mp4\s+"
        r"-f\s+image2pipe\s+-pix_fmt\s+gray\s+-vcodec\s+rawvideo\s+-\s*"
        r"\|\s*(?:\./analyzer|/home/user/analyzer)\s*(?:>|1>)\s*"
        r"(?:/home/user/average_load\.txt|\./average_load\.txt|average_load\.txt)(?:\s|$)",
        re.MULTILINE
    )
    assert pipeline_re.search(active_script), (
        "monitor.sh does not contain the required active ffmpeg raw-gray pipeline into analyzer and average_load.txt"
    )

    assert os.path.exists(cron_path), f"Cron file missing: {cron_path}"
    with open(cron_path, "r") as f:
        cron_content = f.read()

    assert "30 2 * * *" in cron_content, "Cron schedule is not set to 2:30 AM every day (expected '30 2 * * *')"
    assert "/home/user/monitor.sh" in cron_content, "Cron file does not execute /home/user/monitor.sh"
    active_cron = "\n".join(line for line in cron_content.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"^\s*30\s+2\s+\*\s+\*\s+\*\s+/home/user/monitor\.sh\s*$", active_cron, re.MULTILINE), (
        "No active cron entry runs /home/user/monitor.sh every day at 2:30 AM"
    )

    run_result = subprocess.run(
        [script_path], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, check=False
    )
    assert run_result.returncode == 0, (
        "monitor.sh failed: " + run_result.stderr.decode(errors="replace")
    )
    with open("/home/user/average_load.txt", "rb") as f:
        monitored = parse_single_float(f.read(), "monitor.sh output")
    target = compute_target_load()
    assert abs(monitored - target) <= 0.5, (
        f"monitor.sh produced {monitored}, not the video-derived target {target:.2f}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
