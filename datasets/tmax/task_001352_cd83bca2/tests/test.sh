#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import socket
import sqlite3
import subprocess

import pytest
import requests

_rng = random.SystemRandom()


def _dynamic_expression_cases(count=12):
    cases = []
    for _ in range(count):
        a, b, c, d = [_rng.randint(11, 9999) for _ in range(4)]
        divisor = _rng.randint(2, 97)
        quotient = _rng.randint(2, 997)
        dividend = divisor * quotient
        choice = _rng.randrange(4)
        if choice == 0:
            cases.append((f"{a} + {b} * {c} - {d}", a + b * c - d))
        elif choice == 1:
            cases.append((f"{a} * {b} + {dividend} / {divisor}", a * b + quotient))
        elif choice == 2:
            cases.append((f"{a} - {b} - {c} + {d}", a - b - c + d))
        else:
            cases.append((f"{dividend} / {divisor} * {c} + {d}", quotient * c + d))
    return cases


DYNAMIC_CASES = _dynamic_expression_cases()


def test_rust_compilation():
    binary_path = "/app/rust_counter/target/release/rust_counter"
    assert os.path.isfile(binary_path), f"Rust release binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Rust binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Rust release artifact is not an ELF binary"

    word_counts = [
        ("hello world", 2),
        ("single", 1),
        ("one two three four five", 5),
    ]
    for _ in range(6):
        count = _rng.randint(2, 25)
        words = [f"w{_rng.getrandbits(48):012x}" for _ in range(count)]
        word_counts.append((" ".join(words), count))

    for text, expected in word_counts:
        try:
            result = subprocess.run(
                [binary_path, text], capture_output=True, text=True, timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Rust binary timed out during execution.")
        assert result.returncode == 0, (
            f"Rust binary exited with non-zero code: {result.returncode}\n"
            f"Stderr: {result.stderr}"
        )
        assert result.stdout.strip() == str(expected), (
            f"Expected word count {expected} for {text!r}, got {result.stdout!r}"
        )


def test_schema_migration():
    db_path = "/app/video_stats.db"
    assert os.path.isfile(db_path), f"SQLite database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(stats)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    assert "anomalies" in columns, "Column 'anomalies' missing in stats table."

    cursor.execute("SELECT anomalies FROM stats WHERE video_name = 'traffic.mp4'")
    row = cursor.fetchone()
    assert row is not None, "Row for 'traffic.mp4' missing in stats table."
    assert row[0] == 3, f"Expected anomalies to be 3 for traffic.mp4, got {row[0]}."

    conn.close()


def _video_dimensions(path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", path,
        ],
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    stream = json.loads(result.stdout)["streams"][0]
    return int(stream["width"]), int(stream["height"])


def _decode_rgb(path):
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", path,
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        capture_output=True,
        timeout=20,
        check=True,
    )
    return result.stdout


def test_video_fixture():
    frame_path = "/app/frame_30.jpg"
    video_path = "/app/traffic.mp4"
    assert os.path.isfile(frame_path), f"Frame image {frame_path} does not exist."

    with open(frame_path, "rb") as f:
        header = f.read(2)
    assert header == b"\xff\xd8", f"File {frame_path} does not appear to be a valid JPEG."

    width, height = _video_dimensions(video_path)
    frame_size = width * height * 3
    candidate = _decode_rgb(frame_path)
    assert len(candidate) == frame_size, (
        "Extracted JPEG dimensions do not match the source video dimensions"
    )

    all_frames = _decode_rgb(video_path)
    assert len(all_frames) % frame_size == 0, "Could not decode source video frames"
    frame_count = len(all_frames) // frame_size
    assert frame_count > 30, "Source video does not contain frame 30"

    distances = []
    for index in range(frame_count):
        reference = all_frames[index * frame_size:(index + 1) * frame_size]
        distance = sum(abs(a - b) for a, b in zip(candidate, reference))
        distances.append(distance)

    closest = min(range(frame_count), key=distances.__getitem__)
    assert closest == 30, (
        f"/app/frame_30.jpg most closely matches source frame {closest}, not frame 30"
    )


def test_http_evaluate_endpoint():
    url = "http://127.0.0.1:8000/evaluate"
    test_cases = [
        ("10 + 2 * 6", 22),
        ("3 + 5 * 2", 13),
        ("10 - 2", 8),
        ("20 / 4 + 3", 8),
    ] + DYNAMIC_CASES

    for expr, expected in test_cases:
        try:
            response = requests.post(url, json={"expr": expr}, timeout=2)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to HTTP evaluate endpoint: {e}")

        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")

        assert "result" in data, f"Key 'result' missing in JSON response: {data}"
        assert data["result"] == expected, (
            f"Expected result {expected} for expression {expr!r}, got {data['result']}"
        )


def test_http_frame_endpoint():
    url = "http://127.0.0.1:8000/frame"
    frame_path = "/app/frame_30.jpg"

    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP frame endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    with open(frame_path, "rb") as f:
        expected_bytes = f.read()
    assert response.content == expected_bytes, (
        "Returned bytes do not match the contents of /app/frame_30.jpg"
    )


def test_tcp_evaluate_endpoint():
    host = "127.0.0.1"
    port = 8001
    test_cases = [
        ("4 * 4 + 4", 20),
        ("10 - 2", 8),
        ("15 / 3 + 2", 7),
    ] + DYNAMIC_CASES

    for expr, expected in test_cases:
        try:
            with socket.create_connection((host, port), timeout=2) as s:
                s.settimeout(2)
                s.sendall((expr + "\n").encode("utf-8"))
                chunks = []
                while True:
                    chunk = s.recv(1024)
                    if not chunk:
                        break
                    chunks.append(chunk)
                data = b"".join(chunks).decode("utf-8")
        except socket.error as e:
            pytest.fail(f"TCP connection or communication failed: {e}")

        expected_text = f"{expected}\n"
        assert data == expected_text, (
            f"Expected TCP response {expected_text!r} for expression {expr!r}, got {data!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
