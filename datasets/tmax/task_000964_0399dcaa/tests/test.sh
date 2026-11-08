#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import struct
import subprocess
import wave
import zlib

ORACLE_PATH = "/tests/oracle_extractor"
AGENT_PATH = "/home/user/fast_extractor"
SOURCE_PATH = "/home/user/fast_extractor.cpp"


def test_fast_extractor_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent executable missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"
    assert os.path.isfile(SOURCE_PATH), f"C++ source missing at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, "C++ source is empty"

    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes.startswith(b"\x7fELF"), "fast_extractor is not a compiled ELF executable"
    assert agent_bytes != oracle_bytes, "Submitted executable is byte-identical to the reference executable"

    rebuilt_path = "/tmp/fast_extractor_rebuilt"
    build = subprocess.run(
        ["g++", "-O3", SOURCE_PATH, "-o", rebuilt_path],
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert build.returncode == 0, f"fast_extractor.cpp does not compile:\n{build.stderr}"

    random.seed(42)
    N = 50
    min_length = 1000
    max_length = 15000
    min_val = -32768
    max_val = 32767

    for i in range(N):
        length = random.randint(min_length, max_length)
        input_array = [str(random.randint(min_val, max_val)) for _ in range(length)]
        input_str = " ".join(input_array) + "\n"

        oracle_proc = subprocess.run([ORACLE_PATH], input=input_str, text=True, capture_output=True, timeout=20)
        agent_proc = subprocess.run([AGENT_PATH], input=input_str, text=True, capture_output=True, timeout=20)
        rebuilt_proc = subprocess.run([rebuilt_path], input=input_str, text=True, capture_output=True, timeout=20)

        assert oracle_proc.returncode == 0, f"Oracle failed on fuzz test {i+1}"
        assert agent_proc.returncode == 0, f"Agent executable failed on fuzz test {i+1}: {agent_proc.stderr}"
        assert rebuilt_proc.returncode == 0, f"Executable rebuilt from source failed on fuzz test {i+1}: {rebuilt_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()
        rebuilt_out = rebuilt_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on fuzz test {i+1}/{N}.\n"
            f"Input length: {length}\n"
            f"Oracle output: {oracle_out[:100]}...\n"
            f"Agent output: {agent_out[:100]}...\n"
        )
        assert oracle_out == rebuilt_out, (
            f"Source mismatch on fuzz test {i+1}/{N}.\n"
            f"Input length: {length}\n"
            f"Oracle output: {oracle_out[:100]}...\n"
            f"Rebuilt output: {rebuilt_out[:100]}...\n"
        )


def _read_expected_pcm():
    with wave.open("/app/interview.wav", "rb") as audio:
        assert audio.getnchannels() == 1, "Test audio unexpectedly is not mono"
        assert audio.getsampwidth() == 2, "Test audio unexpectedly is not signed 16-bit PCM"
        frames = audio.readframes(audio.getnframes())
    return list(struct.unpack("<{}h".format(len(frames) // 2), frames))


def _validate_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), "sec_plot.png is not a PNG file"
    assert len(data) > 1000, "sec_plot.png is implausibly small"

    pos = 8
    width = height = None
    idat = bytearray()
    saw_iend = False
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        assert pos + 12 + length <= len(data), "Malformed PNG chunk"
        if kind == b"IHDR":
            width, height = struct.unpack(">II", payload[:8])
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            saw_iend = True
            break
        pos += 12 + length

    assert saw_iend and width is not None and idat, "PNG lacks required chunks"
    assert width >= 100 and height >= 100, "Plot dimensions are too small"
    pixels = zlib.decompress(bytes(idat))
    assert len(pixels) > 1000 and len(set(pixels)) > 8, "PNG appears blank or contains no rendered plot"


def test_other_files_exist_and_are_functional():
    transcript_path = "/home/user/transcript.txt"
    script_path = "/home/user/plot_features.py"
    png_path = "/home/user/sec_plot.png"

    assert os.path.exists(transcript_path), "Transcript file /home/user/transcript.txt is missing"
    assert os.path.exists(script_path), "Plotting script /home/user/plot_features.py is missing"
    assert os.path.exists(png_path), "Plot image /home/user/sec_plot.png is missing"
    assert os.path.isfile(transcript_path), "Transcript path is not a regular file"
    assert os.path.isfile(script_path), "Plotting script path is not a regular file"

    pcm = _read_expected_pcm()
    assert pcm and all(sample == 0 for sample in pcm), "The supplied silent transcription fixture was modified"
    transcript_bytes = open(transcript_path, "rb").read()
    transcript = transcript_bytes.decode("utf-8")
    assert transcript_bytes == b"", "The silent source audio must have an empty raw transcript"
    assert not re.search(r"\[?\d{1,2}:\d{2}(?::\d{2})?\]?", transcript), "Transcript contains timestamps"

    source = open(script_path, "r", encoding="utf-8").read()
    assert source.strip(), "Plotting script is empty"
    ast.parse(source, filename=script_path)
    lowered = source.lower()
    assert "title" in lowered, "Plotting script does not specify a title"
    assert any(token in lowered for token in ("xlabel", "xaxis_title", "set_xlabel")), "Plotting script does not label the x axis"
    assert any(token in lowered for token in ("ylabel", "yaxis_title", "set_ylabel")), "Plotting script does not label the y axis"

    backup_path = "/home/user/fast_extractor.verifier-real"
    log_path = "/tmp/plot_extractor_input.txt"
    wrapper = '''#!/usr/bin/env python3
import subprocess
import sys
payload = sys.stdin.read()
with open("/tmp/plot_extractor_input.txt", "w") as f:
    f.write(payload)
proc = subprocess.run(["/home/user/fast_extractor.verifier-real"], input=payload, text=True, capture_output=True)
sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
sys.exit(proc.returncode)
'''

    if os.path.exists(log_path):
        os.unlink(log_path)
    if os.path.exists(png_path):
        os.unlink(png_path)

    os.rename(AGENT_PATH, backup_path)
    try:
        with open(AGENT_PATH, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(AGENT_PATH, 0o755)
        proc = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=120,
        )
    finally:
        if os.path.exists(AGENT_PATH):
            os.unlink(AGENT_PATH)
        os.rename(backup_path, AGENT_PATH)
        os.chmod(AGENT_PATH, 0o755)

    assert proc.returncode == 0, f"Plotting script failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isfile(log_path), "Plotting script did not invoke /home/user/fast_extractor"
    submitted_pcm = [int(value) for value in open(log_path, "r", encoding="utf-8").read().split()]
    assert submitted_pcm == pcm, "Plotting script did not pass the audio's signed 16-bit PCM samples to the extractor"
    assert os.path.isfile(png_path), "Plotting script did not generate /home/user/sec_plot.png"
    _validate_png(png_path)
TEST_EOF

chmod +x /tests/oracle_extractor
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
