#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/url_sanitizer.py"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
VIDEO_PATH = "/app/sequence.mp4"


def video_cycle():
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-vf", "fps=1,scale=1:1", "-f", "rawvideo",
            "-pix_fmt", "rgb24", "pipe:1",
        ],
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert len(result.stdout) >= 9 and len(result.stdout) % 3 == 0

    observed = []
    names = ("red", "green", "blue")
    for offset in range(0, len(result.stdout), 3):
        rgb = result.stdout[offset:offset + 3]
        strongest = max(range(3), key=lambda i: rgb[i])
        assert rgb[strongest] >= max(rgb[(strongest + 1) % 3], rgb[(strongest + 2) % 3]) + 20
        name = names[strongest]
        if not observed or observed[-1] != name:
            observed.append(name)

    assert len(observed) == 3, f"Expected three color frames, got {observed}"
    assert set(observed) == {"red", "green", "blue"}
    return observed


def line_is_valid(line, cycle):
    states = [segment for segment in line.split("/") if segment in set(cycle)]
    successor = {cycle[i]: cycle[(i + 1) % len(cycle)] for i in range(len(cycle))}
    return all(current == successor[previous] for previous, current in zip(states, states[1:]))


def test_sanitizer_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No clean corpus files found"

    modified_files = []
    for filename in clean_files:
        input_path = os.path.join(CLEAN_DIR, filename)
        with tempfile.NamedTemporaryFile(mode="w+", delete=False) as tmp:
            output_path = tmp.name
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, input_path, output_path],
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, f"Script failed on {filename} with return code {result.returncode}:\n{result.stderr}"
            with open(input_path, "r") as f:
                expected_lines = f.read().splitlines()
            with open(output_path, "r") as f:
                actual_lines = f.read().splitlines()
            if expected_lines != actual_lines:
                modified_files.append(filename)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified: {', '.join(modified_files)}")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "No evil corpus files found"

    bypassed_files = []
    for filename in evil_files:
        input_path = os.path.join(EVIL_DIR, filename)
        with tempfile.NamedTemporaryFile(mode="w+", delete=False) as tmp:
            output_path = tmp.name
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, input_path, output_path],
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, f"Script failed on {filename} with return code {result.returncode}:\n{result.stderr}"
            with open(output_path, "r") as f:
                actual_lines = f.read().splitlines()
            if len(actual_lines) > 0:
                bypassed_files.append(filename)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_unseen_mixed_inputs_against_video_cycle():
    cycle = video_cycle()
    rng = secrets.SystemRandom()
    colors = list(cycle)
    lines = []

    for _ in range(300):
        segments = []
        for _ in range(rng.randint(1, 14)):
            if rng.random() < 0.58:
                segments.append(rng.choice(colors))
            else:
                segments.append("x" + secrets.token_hex(rng.randint(2, 7)))
        path = "/" + "/".join(segments)
        if rng.random() < 0.25:
            path = "/service/" + secrets.token_hex(4) + path
        if rng.random() < 0.2:
            path += "/"
        lines.append(path)

    # Guarantee both retained and rejected records independently of random choices.
    lines.extend([
        "/dynamic/" + cycle[0] + "/noise/" + cycle[1] + "/" + cycle[2],
        "/dynamic/" + cycle[1],
        "/dynamic/no/state/segments",
        "/dynamic/" + cycle[0] + "/noise/" + cycle[2],
        "/dynamic/" + cycle[1] + "/" + cycle[1],
        "/dynamic/" + cycle[2] + "/" + cycle[1],
    ])
    rng.shuffle(lines)

    expected_lines = [line for line in lines if line_is_valid(line, cycle)]
    assert expected_lines and len(expected_lines) < len(lines)

    workdir = tempfile.mkdtemp(prefix="url-sanitizer-unseen-")
    input_path = os.path.join(workdir, "incoming-" + secrets.token_hex(8) + ".dat")
    output_path = os.path.join(workdir, "result-" + secrets.token_hex(8) + ".dat")
    try:
        with open(input_path, "wb") as f:
            f.write(b"".join((line + "\n").encode("utf-8") for line in lines))

        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_path, output_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"Script failed on unseen input:\n{result.stderr}"
        assert os.path.isfile(output_path), "Sanitizer did not create the requested output file"

        with open(output_path, "rb") as f:
            actual = f.read()
        expected = b"".join((line + "\n").encode("utf-8") for line in expected_lines)
        assert actual == expected, "Sanitizer output did not match recomputed transition validity"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
