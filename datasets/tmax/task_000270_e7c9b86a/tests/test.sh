#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import pytest

VIDEO_PATH = "/app/reference_run.mp4"
PROCESSOR_PATH = "/home/user/event_processor"


def active_frames_from_video():
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-vf", "crop=10:10:0:0",
            "-pix_fmt", "rgb24", "-f", "rawvideo", "-",
        ],
        capture_output=True,
    )
    assert proc.returncode == 0, f"Failed to decode reference video: {proc.stderr.decode(errors='replace')}"

    frame_size = 10 * 10 * 3
    assert len(proc.stdout) % frame_size == 0, "Decoded video data contains a partial frame"

    active = []
    for frame_number, offset in enumerate(range(0, len(proc.stdout), frame_size)):
        frame = proc.stdout[offset:offset + frame_size]
        luminance_sum = 0.0
        for i in range(0, frame_size, 3):
            r, g, b = frame[i], frame[i + 1], frame[i + 2]
            luminance_sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance_sum / 100 > 128:
            active.append(frame_number)
    return active


def expected_processor_output(input_data):
    frames = set()
    for line in input_data.splitlines():
        value = line.strip()
        if value.isdigit():
            frames.add(int(value))

    sorted_frames = sorted(frames)
    events = []
    if sorted_frames:
        start = prev = sorted_frames[0]
        for frame in sorted_frames[1:]:
            if frame == prev + 1:
                prev = frame
            else:
                events.append({"start": start, "end": prev})
                start = prev = frame
        events.append({"start": start, "end": prev})

    return json.dumps(events, separators=(",", ":"))


def test_extracted_frames_correct():
    extracted_path = "/home/user/extracted_frames.txt"
    assert os.path.exists(extracted_path), f"Extracted frames file missing at {extracted_path}"

    with open(extracted_path, "r") as f:
        lines = f.read().strip().splitlines()

    actual_frames = []
    for line in lines:
        line = line.strip()
        if line:
            assert line.isdigit(), f"Non-integer found in extracted_frames.txt: {line}"
            actual_frames.append(int(line))

    expected_frames = active_frames_from_video()
    assert sorted(actual_frames) == sorted(expected_frames), "Extracted frames do not match the active decoded frames from the video."


def test_event_processor_exists_and_executable():
    assert os.path.exists(PROCESSOR_PATH), f"Event processor missing at {PROCESSOR_PATH}"
    assert os.path.isfile(PROCESSOR_PATH), f"{PROCESSOR_PATH} is not a file"
    assert os.access(PROCESSOR_PATH, os.X_OK), f"Event processor at {PROCESSOR_PATH} is not executable"


def test_event_processor_fuzz_equivalence():
    random.seed(42)
    iterations = 500

    for i in range(iterations):
        num_lines = random.randint(0, 500)
        frames = [str(random.randint(0, 99999)) for _ in range(num_lines)]

        if frames:
            num_dups = random.randint(0, int(len(frames) * 0.1))
            frames.extend(random.choices(frames, k=num_dups))

        frames.extend([""] * random.randint(0, 5))
        random.shuffle(frames)
        input_data = "\n".join(frames)
        expected_output = expected_processor_output(input_data)

        agent_proc = subprocess.run(
            [PROCESSOR_PATH],
            input=input_data,
            text=True,
            capture_output=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent processor failed (exit code {agent_proc.returncode}) on iteration {i}. "
            f"Stderr: {agent_proc.stderr}"
        )

        agent_output = agent_proc.stdout.strip()
        try:
            agent_json = json.loads(agent_output) if agent_output else []
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on iteration {i}. Output: {agent_output}")

        expected_json = json.loads(expected_output)
        assert agent_json == expected_json, (
            f"Mismatch on iteration {i}.\n"
            f"Input lines: {len(frames)}\n"
            f"Expected: {expected_output}\n"
            f"Actual: {agent_output}"
        )
        assert agent_output == expected_output, (
            f"Incorrect JSON serialization on iteration {i}.\n"
            f"Expected: {expected_output}\n"
            f"Actual: {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
