#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import string
import subprocess
import pytest


def get_video_info(path):
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", path]
    output = subprocess.check_output(cmd)
    info = json.loads(output)
    stream = info['streams'][0]
    return int(stream['width']), int(stream['height'])


def count_blue_frames(path):
    w, h = get_video_info(path)
    frame_size = w * h * 3
    cmd = ["ffmpeg", "-i", path, "-f", "image2pipe", "-vcodec", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    blue_count = 0
    expected_frame = b'\x00\x00\xff' * (w * h)

    while True:
        frame = proc.stdout.read(frame_size)
        if not frame or len(frame) < frame_size:
            break
        if frame == expected_frame:
            blue_count += 1

    proc.stdout.close()
    proc.wait()
    return blue_count


def simulate_sanitizer(input_text, N):
    lines = input_text.split('\n')
    output_lines = []
    last_seen = {}

    for line in lines:
        if not line:
            continue
        parts = line.split(',')
        if len(parts) != 4:
            continue
        ts_str, vid_str, speed_str, lp = parts
        try:
            ts = int(ts_str)
            vid = int(vid_str)
        except ValueError:
            continue

        if not all(('A' <= c <= 'Z') or ('0' <= c <= '9') or c == '-' for c in lp):
            continue

        if vid in last_seen and abs(ts - last_seen[vid]) <= N:
            continue

        last_seen[vid] = ts
        masked_lp = lp if len(lp) <= 2 else '*' * (len(lp) - 2) + lp[-2:]
        output_lines.append(f"{ts},{vid},{speed_str},{masked_lp}")

    return "" if not output_lines else "\n".join(output_lines) + "\n"


@pytest.fixture(scope="session")
def deduplication_window():
    video_path = "/app/fault_log.mp4"
    assert os.path.exists(video_path), f"Video file missing at {video_path}"
    return count_blue_frames(video_path)


@pytest.fixture(scope="session")
def sanitizer_executable():
    source_path = "/home/user/sanitizer.c"
    exe_path = "/home/user/sanitizer"
    assert os.path.isfile(source_path), f"C source missing at {source_path}"
    assert os.path.isfile(exe_path), f"Executable missing at {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File at {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled ELF executable"
    return exe_path


def run_sanitizer(executable, input_text):
    proc = subprocess.run(
        [executable],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=5
    )
    assert proc.returncode == 0, f"Sanitizer crashed or failed with return code {proc.returncode}"
    return proc.stdout


def test_clean_corpus(sanitizer_executable, deduplication_window):
    clean_dir = "/app/corpus/clean/"
    assert os.path.exists(clean_dir), "Clean corpus directory missing"

    files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
    assert len(files) > 0, "No CSV files found in clean corpus"
    failed_files = []

    for filename in files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            input_data = f.read()
        expected_output = simulate_sanitizer(input_data, deduplication_window)
        actual_output = run_sanitizer(sanitizer_executable, input_data)
        if actual_output != expected_output:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} clean modified or processed incorrectly: {', '.join(failed_files)}"


def test_evil_corpus(sanitizer_executable, deduplication_window):
    evil_dir = "/app/corpus/evil/"
    assert os.path.exists(evil_dir), "Evil corpus directory missing"

    files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert len(files) > 0, "No CSV files found in evil corpus"
    failed_files = []

    for filename in files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            input_data = f.read()
        expected_output = simulate_sanitizer(input_data, deduplication_window)
        try:
            actual_output = run_sanitizer(sanitizer_executable, input_data)
            if actual_output != expected_output:
                failed_files.append(filename)
        except Exception:
            failed_files.append(filename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} evil bypassed or crashed: {', '.join(failed_files)}"


def random_valid_plate(rng, length=None):
    alphabet = string.ascii_uppercase + string.digits + '-'
    if length is None:
        length = rng.randint(1, 24)
    return ''.join(rng.choice(alphabet) for _ in range(length))


def test_generated_hidden_streams(sanitizer_executable, deduplication_window):
    rng = secrets.SystemRandom()
    N = deduplication_window
    illegal_plates = [
        "abc-123", "BAD PLATE", "DROP;TABLE", "UNDER_SCORE", "SLASH/12",
        "QUOTE'12", "DOT.123", "éABC12", "ABC+12", "ABC,12"
    ]

    for batch in range(8):
        base = rng.randint(1700000000, 1900000000)
        target = rng.randint(100000, 900000)
        other = target + rng.randint(1000, 9000)
        rows = []

        def add(ts, vid, plate, speed=None):
            if speed is None:
                speed = f"{rng.randint(0, 180)}.{rng.randint(0, 999):03d}"
            rows.append((ts, rng.random(), f"{ts},{vid},{speed},{plate}"))

        add(base, target, random_valid_plate(rng, 8))
        add(base + N, target, "bad-lower")
        add(base + N, target, random_valid_plate(rng, 7))
        add(base + N + 1, target, random_valid_plate(rng, 9))
        add(base + 2 * N + 1, target, random_valid_plate(rng, 5))
        add(base + 2 * N + 2, target, random_valid_plate(rng, 12))

        add(base + 1, other, random_valid_plate(rng, 1))
        add(base + N + 1, other, random_valid_plate(rng, 2))
        add(base + N + 2, other, random_valid_plate(rng, 3))

        for i, plate in enumerate(illegal_plates):
            add(base + 3 + i, other + 100 + i, plate)

        add(base + 20, other + 500, random_valid_plate(rng, 257))
        add(base + 21, other + 501, "A" * 2048 + ";")

        current = base + 100
        ids = [target + 20000 + i for i in range(12)]
        for i in range(140):
            current += rng.randint(0, max(1, N + 2))
            vid = rng.choice(ids)
            if rng.random() < 0.72:
                plate = random_valid_plate(rng)
            else:
                valid = random_valid_plate(rng, rng.randint(2, 18))
                bad = rng.choice(['a', '_', ' ', ';', '/', '.', '@'])
                pos = rng.randrange(len(valid) + 1)
                plate = valid[:pos] + bad + valid[pos:]
            add(current, vid, plate)

        rows.sort(key=lambda item: (item[0], item[1]))
        input_data = '\n'.join(item[2] for item in rows) + '\n'
        expected_output = simulate_sanitizer(input_data, N)
        actual_output = run_sanitizer(sanitizer_executable, input_data)
        assert actual_output == expected_output, f"Generated adversarial stream {batch} was processed incorrectly"


def test_state_resets_between_invocations(sanitizer_executable, deduplication_window):
    rng = secrets.SystemRandom()
    ts = rng.randint(1700000000, 1900000000)
    vid = rng.randint(10000, 99999)
    input_data = f"{ts},{vid},42.50,{random_valid_plate(rng, 10)}\n"
    expected = simulate_sanitizer(input_data, deduplication_window)
    assert run_sanitizer(sanitizer_executable, input_data) == expected
    assert run_sanitizer(sanitizer_executable, input_data) == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
