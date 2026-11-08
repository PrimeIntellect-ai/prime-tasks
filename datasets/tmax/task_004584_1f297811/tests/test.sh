#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time

import cv2


def legacy_env():
    env = os.environ.copy()
    legacy_lib_path = "/opt/legacy_libs"
    if "LD_LIBRARY_PATH" in env:
        env["LD_LIBRARY_PATH"] = f"{legacy_lib_path}:{env['LD_LIBRARY_PATH']}"
    else:
        env["LD_LIBRARY_PATH"] = legacy_lib_path
    return env


def parse_total(stdout):
    match = re.fullmatch(r"\s*Total sum:\s*(-?\d+)\s*", stdout)
    assert match, f"Unexpected tool output: {stdout!r}"
    return int(match.group(1))


def expected_total(values):
    prefix = 0
    total = 0
    for value in values:
        prefix += value
        total += prefix
    return total


def test_crash_frame():
    path = "/home/user/crash_frame.txt"
    assert os.path.isfile(path), f"Missing output file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "142", f"Expected crash frame to be '142', got '{content}'"

    capture = cv2.VideoCapture("/app/incident_record.mp4")
    anomalies = []
    frame_number = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        b, g, r = frame.mean(axis=(0, 1))
        if r > 240 and g < 20 and b < 20:
            anomalies.append(frame_number)
        frame_number += 1
    capture.release()
    assert anomalies == [int(content)], (
        f"Reported frame {content}, but video-derived solid-red frames were {anomalies}"
    )


def test_fixed_tool_exists():
    path = "/home/user/fixed_tool"
    assert os.path.isfile(path), f"Missing compiled executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fixed_tool must be a compiled ELF executable"


def test_fixed_source_builds_and_matches_behavior(tmp_path):
    source = "/app/sync_tool.c"
    assert os.path.isfile(source), f"Missing repaired source: {source}"
    rebuilt = str(tmp_path / "rebuilt_tool")
    build = subprocess.run(
        ["gcc", "-O2", "-o", rebuilt, source, "-L/opt/legacy_libs", "-lcustom_math"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build.returncode == 0, f"Repaired source does not compile: {build.stderr}"

    rng = secrets.SystemRandom()
    values = [rng.randint(-2000, 2000) for _ in range(12037)]
    values[rng.randrange(len(values))] = -50000
    values[rng.randrange(len(values))] = rng.randint(30000, 70000)
    data_path = tmp_path / "held_out.dat"
    data_path.write_text("".join(f"{value}\n" for value in values))
    expected = expected_total(values)

    for executable in ("/home/user/fixed_tool", rebuilt):
        result = subprocess.run(
            [executable, str(data_path)],
            env=legacy_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, (
            f"{executable} crashed or failed with return code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
        assert parse_total(result.stdout) == expected, (
            f"{executable} computed the wrong result for held-out telemetry"
        )


def test_fixed_tool_performance(tmp_path):
    executable = "/home/user/fixed_tool"
    assert os.path.isfile(executable), "Executable not found"

    # Create a large test data file
    test_data_path = "/app/large_test_data.dat"
    if not os.path.exists(test_data_path):
        with open(test_data_path, "w") as f:
            # Write 1,000,000 lines of dummy telemetry data
            f.write("10\n" * 1000000)

    # Set up environment for the legacy library
    env = legacy_env()

    # Measure runtime
    start_time = time.perf_counter()
    result = subprocess.run(
        [executable, test_data_path],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    end_time = time.perf_counter()
    runtime = end_time - start_time

    assert result.returncode == 0, f"Executable crashed or failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert parse_total(result.stdout) == 5000005000000, "Incorrect result for massive telemetry input"

    threshold = 0.2
    assert runtime <= threshold, f"Performance metric failed: Runtime was {runtime:.4f}s, threshold is <= {threshold}s"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
