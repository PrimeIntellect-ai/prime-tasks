#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import tempfile
import pytest


def test_step1_subtitle_extraction():
    srt_path = "/home/user/reference.srt"
    assert os.path.exists(srt_path), f"Extracted subtitle file {srt_path} does not exist."
    assert os.path.isfile(srt_path), f"{srt_path} is not a file."
    assert os.path.getsize(srt_path) > 0, f"Extracted subtitle file {srt_path} is empty."

    with open(srt_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "-->" in content, f"{srt_path} does not appear to be a valid SRT file (missing '-->')."

    with tempfile.TemporaryDirectory() as tmpdir:
        expected_path = os.path.join(tmpdir, "expected.srt")
        proc = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-y",
                "-i", "/app/reference_video.mp4",
                "-map", "0:1", "-c:s", "srt", expected_path,
            ],
            capture_output=True,
            text=True,
        )
        assert proc.returncode == 0, f"Could not extract reference subtitle stream: {proc.stderr}"

        with open(expected_path, "rb") as f:
            expected = f.read()
        with open(srt_path, "rb") as f:
            actual = f.read()

    assert actual == expected, "reference.srt is not the exact subtitle extracted from stream 0:1."


def generate_fuzz_data(n=1000):
    random.seed(42)
    lines = []
    for _ in range(n):
        choice = random.random()
        if choice < 0.4:
            hh = f"{random.randint(0, 99):02d}"
            mm = f"{random.randint(0, 59):02d}"
            ss = f"{random.randint(0, 59):02d}"
            mmm = f"{random.randint(0, 999):03d}"
            speaker = "".join(random.choices(string.ascii_uppercase + string.digits, k=random.randint(2, 10)))
            text_len = random.randint(1, 150)
            text = "".join(random.choices(string.ascii_letters + string.digits + " !@#$%^&*()", k=text_len))
            lines.append(f"{hh}:{mm}:{ss}.{mmm} - <{speaker}> : {text}")
        elif choice < 0.7:
            hh = f"{random.randint(0, 99):02d}"
            mm = f"{random.randint(0, 59):02d}"
            ss = f"{random.randint(0, 59):02d}"
            mmm = f"{random.randint(0, 999):03d}"
            speaker = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 15)))
            text_len = random.randint(1, 100)
            text = "".join(random.choices(string.ascii_letters + string.digits + " !@#$%^&*()", k=text_len))
            sep1 = random.choice([" - <", "-<", " -< ", " - < "])
            sep2 = random.choice(["> : ", ">:", "> :", " > : "])
            lines.append(f"{hh}:{mm}:{ss}.{mmm}{sep1}{speaker}{sep2}{text}")
        else:
            length = random.randint(10, 200)
            lines.append("".join(random.choices(string.printable.replace('\n', ''), k=length)))

    return "\n".join(lines) + "\n"


def expected_output(lines):
    pattern = re.compile(r'^(\d{2}:\d{2}:\d{2}\.\d{3}) - <([A-Z0-9]{2,10})> : (.*)$')
    output = []
    for line in lines:
        match = pattern.match(line)
        if match:
            time_val, speaker, text = match.groups()
            output.append(f'<trans unit="{speaker}" time="{time_val}">{text}</trans>')
        else:
            output.append('<error>MALFORMED</error>')
    return output


def test_step2_stream_parser_fuzz_equivalence():
    student_script = "/home/user/stream_parser.py"
    assert os.path.exists(student_script), f"Student script {student_script} does not exist."
    assert os.path.isfile(student_script), f"{student_script} is not a file."

    fuzz_input = generate_fuzz_data(1000)
    input_lines = fuzz_input.split("\n")[:-1]
    oracle_output = expected_output(input_lines)

    student_proc = subprocess.run(
        ["python3", student_script],
        input=fuzz_input,
        text=True,
        capture_output=True,
    )

    if student_proc.returncode != 0:
        pytest.fail(f"Student script crashed with return code {student_proc.returncode}.\nStderr: {student_proc.stderr}")

    student_output = student_proc.stdout.splitlines()

    assert len(student_output) == len(oracle_output), \
        f"Output line count mismatch. Expected {len(oracle_output)}, got {len(student_output)}."

    for i, (oracle_line, student_line) in enumerate(zip(oracle_output, student_output)):
        if oracle_line != student_line:
            pytest.fail(
                f"Mismatch at line {i+1}:\n"
                f"Input:    {repr(input_lines[i])}\n"
                f"Expected: {repr(oracle_line)}\n"
                f"Got:      {repr(student_line)}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
