#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import struct
import subprocess
import time
import wave

import pytest

OUTPUT_MP3 = "/home/user/archived_call_001.mp3"
SCRIPT = "/home/user/archive_audio.py"
SOURCE_WAV = "/app/call_record_001.wav"
SEGMENTS_FILE = "/app/call_001_segments.txt"
SAMPLE_RATE = 16000

# Use content-varying verification input so duration-only output cannot pass.
SEGMENTS = [
    (0.0, 8.0, "SPEECH"),
    (8.0, 14.0, "HOLD_MUSIC"),
    (14.0, 26.0, "SPEECH"),
    (26.0, 34.0, "HOLD_MUSIC"),
    (34.0, 54.0, "SPEECH"),
]
SECOND_FREQUENCIES = [220 + 13 * i for i in range(54)]
EXPECTED_FREQUENCIES = [
    SECOND_FREQUENCIES[i]
    for start, end, label in SEGMENTS if label == "SPEECH"
    for i in range(int(start), int(end))
]


def create_verification_inputs():
    os.makedirs("/app", exist_ok=True)
    with wave.open(SOURCE_WAV, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        for frequency in SECOND_FREQUENCIES:
            frames = bytearray()
            for i in range(SAMPLE_RATE):
                value = int(12000 * math.sin(2 * math.pi * frequency * i / SAMPLE_RATE))
                frames.extend(struct.pack("<h", value))
            wav.writeframes(frames)
    with open(SEGMENTS_FILE, "w", encoding="utf-8") as segments:
        for start, end, label in SEGMENTS:
            segments.write(f"{start:.2f}\t{end:.2f}\t{label}\n")


def has_atomic_move(source):
    """Recognize an actual Python rename/move call (including an mv subprocess)."""
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr in {"replace", "rename", "move"}:
            return True
        if isinstance(func, ast.Name) and func.id in {"replace", "rename", "move"}:
            return True
        # Also permit subprocess/os.system invocation of the standard mv utility.
        if isinstance(func, ast.Attribute) and func.attr in {"run", "call", "check_call", "check_output", "Popen", "system"}:
            constants = [n.value for n in ast.walk(node) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
            if any(value == "mv" or value.startswith("mv ") or " /bin/mv " in f" {value} " for value in constants):
                return True
    return False


def execute_submission_and_check_atomicity():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"Expected {SCRIPT} to be a regular file."
    assert not os.path.islink(SCRIPT), f"Expected {SCRIPT} to be the submitted Python script, not a symlink."

    with open(SCRIPT, "r", encoding="utf-8") as handle:
        source = handle.read()
    assert has_atomic_move(source), "The script does not perform a rename/move for the final atomic publication step."

    create_verification_inputs()

    # A correct atomic replacement leaves this old destination wholly intact until
    # the completed temporary MP3 is renamed over it.
    sentinel = b"incomplete-output-must-never-be-observable\n" * 1700
    with open(OUTPUT_MP3, "wb") as handle:
        handle.write(sentinel)
    initial = os.stat(OUTPUT_MP3)
    initial_identity = (initial.st_dev, initial.st_ino)
    initial_size = initial.st_size
    initial_mtime = initial.st_mtime_ns

    proc = subprocess.Popen(
        ["python3", SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    violation = None
    published_state = None
    deadline = time.monotonic() + 90

    while proc.poll() is None:
        if time.monotonic() > deadline:
            proc.kill()
            proc.wait()
            pytest.fail("archive_audio.py did not finish within 90 seconds")
        try:
            state = os.stat(OUTPUT_MP3)
        except FileNotFoundError:
            violation = "The final path disappeared before publication; replacement was not atomic."
            break

        identity = (state.st_dev, state.st_ino)
        if identity == initial_identity:
            if state.st_size != initial_size or state.st_mtime_ns != initial_mtime:
                violation = "The final MP3 was modified in place instead of being atomically replaced."
                break
        else:
            current = (identity, state.st_size, state.st_mtime_ns)
            if published_state is None:
                published_state = current
            elif current != published_state:
                violation = "The published final MP3 continued changing after it became visible."
                break
        time.sleep(0.001)

    if violation:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        pytest.fail(violation)

    return_code = proc.wait()
    assert return_code == 0, f"archive_audio.py exited with status {return_code}."
    assert os.path.isfile(OUTPUT_MP3), f"Output file {OUTPUT_MP3} is missing after running the script."
    final = os.stat(OUTPUT_MP3)
    assert (final.st_dev, final.st_ino) != initial_identity, "The destination was not atomically replaced with a temporary file."


def get_expected_duration():
    """Calculate the total duration of SPEECH segments."""
    duration = 0.0
    with open(SEGMENTS_FILE, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 3 and parts[2] == 'SPEECH':
                duration += float(parts[1]) - float(parts[0])
    return duration


def get_media_info(file_path):
    """Use ffprobe to get media properties."""
    cmd = [
        'ffprobe', '-v', 'quiet', '-print_format', 'json',
        '-show_format', '-show_streams', file_path
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        pytest.fail(f"ffprobe failed to read {file_path}")
    return json.loads(result.stdout)


def test_00_script_runs_and_uses_atomic_replacement():
    execute_submission_and_check_atomicity()


def test_output_file_exists_and_size():
    """Test that the output MP3 exists and is within the size limit."""
    assert os.path.exists(OUTPUT_MP3), f"Output file {OUTPUT_MP3} is missing."
    assert os.path.isfile(OUTPUT_MP3), f"Expected {OUTPUT_MP3} to be a file."

    file_size = os.path.getsize(OUTPUT_MP3)
    assert file_size <= 500000, f"File size {file_size} bytes exceeds the limit of 500000 bytes."
    assert file_size > 0, "Output file is empty."


def test_output_audio_properties():
    """Test that the output MP3 has the correct format, sample rate, channels, and duration."""
    assert os.path.exists(OUTPUT_MP3), f"Output file {OUTPUT_MP3} is missing."

    info = get_media_info(OUTPUT_MP3)
    streams = info.get('streams', [])
    assert len(streams) > 0, "No audio streams found in the output file."

    audio_stream = next((s for s in streams if s.get('codec_type') == 'audio'), None)
    assert audio_stream is not None, "No audio stream found in the output file."

    codec_name = audio_stream.get('codec_name')
    assert codec_name == 'mp3', f"Expected codec 'mp3', got '{codec_name}'."

    sample_rate = audio_stream.get('sample_rate')
    assert sample_rate == '16000', f"Expected sample rate 16000 Hz, got {sample_rate} Hz."

    channels = audio_stream.get('channels')
    assert channels == 1, f"Expected 1 channel (mono), got {channels} channels."

    bit_rate = int(audio_stream.get('bit_rate', info.get('format', {}).get('bit_rate', 0)))
    assert 30000 <= bit_rate <= 34000, f"Expected bit rate around 32000 bps, got {bit_rate} bps."

    expected_duration = get_expected_duration()
    actual_duration = float(info.get('format', {}).get('duration', 0.0))
    duration_diff = abs(actual_duration - expected_duration)
    assert duration_diff <= 1.0, f"Expected duration ~{expected_duration:.2f}s, got {actual_duration:.2f}s. Ensure only SPEECH segments were included."


def test_output_contains_the_selected_source_intervals_in_order():
    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", OUTPUT_MP3,
            "-f", "s16le", "-acodec", "pcm_s16le", "-ac", "1", "-ar", str(SAMPLE_RATE), "-"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert decoded.returncode == 0, f"Could not decode output MP3: {decoded.stderr.decode(errors='replace')}"
    sample_count = len(decoded.stdout) // 2
    samples = struct.unpack(f"<{sample_count}h", decoded.stdout[:sample_count * 2])

    expected_samples = len(EXPECTED_FREQUENCIES) * SAMPLE_RATE
    assert abs(sample_count - expected_samples) <= SAMPLE_RATE, "Decoded output does not have the expected speech-only length."

    # Every source second has a distinct tone. Measure the central part of each
    # output second, away from cut boundaries, and require the selected sequence.
    for second, expected_frequency in enumerate(EXPECTED_FREQUENCIES):
        start = second * SAMPLE_RATE + int(0.20 * SAMPLE_RATE)
        end = second * SAMPLE_RATE + int(0.80 * SAMPLE_RATE)
        assert end <= sample_count, f"Output ended before expected speech block {second}."
        crossings = 0
        previous = samples[start]
        for value in samples[start + 1:end]:
            if previous <= 0 < value:
                crossings += 1
            previous = value
        measured_frequency = crossings / 0.60
        assert abs(measured_frequency - expected_frequency) <= 4.0, (
            f"Audio content mismatch at output second {second}: expected source tone "
            f"{expected_frequency} Hz, measured about {measured_frequency:.1f} Hz."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
