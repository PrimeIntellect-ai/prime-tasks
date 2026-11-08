#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest
import math


def expected_video_variance():
    video = "/app/dashboard_cam.mp4"
    assert os.path.isfile(video), f"Video fixture {video} does not exist."

    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x", video,
        ],
        text=True,
        capture_output=True,
    )
    assert probe.returncode == 0, f"ffprobe failed: {probe.stderr}"
    width, height = map(int, probe.stdout.strip().split("x"))
    frame_size = width * height

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        capture_output=True,
    )
    assert decoded.returncode == 0, f"ffmpeg failed: {decoded.stderr.decode(errors='replace')}"
    assert decoded.stdout and len(decoded.stdout) % frame_size == 0, "Decoded video contained incomplete frames."

    count = 0
    mean = 0.0
    m2 = 0.0
    for offset in range(0, len(decoded.stdout), frame_size):
        frame = decoded.stdout[offset:offset + frame_size]
        brightness = sum(frame) / frame_size
        count += 1
        delta = brightness - mean
        mean += delta / count
        m2 += delta * (brightness - mean)

    return 0.0 if count < 2 else m2 / (count - 1)


def test_final_variance_file():
    variance_file = "/home/user/final_variance.txt"
    assert os.path.isfile(variance_file), f"Expected output file {variance_file} does not exist."

    with open(variance_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {variance_file} is empty."
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {variance_file} is not a valid float: {content}")

    expected = expected_video_variance()
    assert math.isclose(val, expected, rel_tol=1e-2, abs_tol=5e-7), (
        f"Final variance {val} is not close to the video-derived expected value {expected:.6f}."
    )


def test_stability_calc_executable():
    agent_bin = "/home/user/stability_calc"
    oracle_bin = "/app/oracle_stability_calc"
    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} does not exist."
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."
    with open(agent_bin, "rb") as agent, open(oracle_bin, "rb") as oracle:
        assert agent.read() != oracle.read(), "Agent binary must not be a byte-identical copy of the oracle."


def test_fuzz_equivalence():
    agent_bin = "/home/user/stability_calc"
    oracle_bin = "/app/oracle_stability_calc"

    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} missing."
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable."

    random.seed(42)
    num_tests = 50

    for i in range(num_tests):
        seq_len = random.randint(10, 1000)
        input_floats = [random.uniform(0.0, 255.0) for _ in range(seq_len)]
        input_str = "\n".join(f"{x:.6f}" for x in input_floats) + "\n"

        proc_oracle = subprocess.run(
            [oracle_bin],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert proc_oracle.returncode == 0, f"Oracle failed on input {i}"
        oracle_out = proc_oracle.stdout.strip()

        proc_agent = subprocess.run(
            [agent_bin],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert proc_agent.returncode == 0, f"Agent binary failed on input {i}\nError: {proc_agent.stderr}"
        agent_out = proc_agent.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on fuzz test {i} (length {seq_len}).\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}\n"
            f"Input preview: {input_str[:100]}..."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
