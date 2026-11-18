#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import socket
import sqlite3
import subprocess
import pytest


def decoded_brightness():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
         "/app/signal.mp4"],
        check=True, capture_output=True, text=True
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    decode = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/signal.mp4",
         "-map", "0:v:0", "-vsync", "0", "-f", "rawvideo",
         "-pix_fmt", "gray", "pipe:1"],
        check=True, capture_output=True
    )
    frame_size = width * height
    assert frame_size > 0
    assert len(decode.stdout) % frame_size == 0, "Decoded video has partial frames"
    frames = [decode.stdout[i:i + frame_size]
              for i in range(0, len(decode.stdout), frame_size)]
    assert len(frames) == 10, f"Expected 10 decoded video frames, got {len(frames)}"
    return [sum(frame) / frame_size for frame in frames]


def listening_server_pid(port):
    inodes = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(pid)
        except OSError:
            continue
    return None


def assert_cpp_sql_server(pid):
    exe_path = f"/proc/{pid}/exe"
    with open(exe_path, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), "Port 8000 must be served by a compiled native program"

    binary_text = binary.decode("latin1", errors="ignore").upper()
    for token in ("SQLITE3_", "OVER", "PRECEDING", "FOLLOWING", "JOIN"):
        assert token in binary_text, f"Server executable does not contain required SQLite/window-query token: {token}"

    candidates = []
    for root in ("/app", "/home/user", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in (".cache", ".git", "node_modules")]
            for name in files:
                if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                    candidates.append(os.path.join(directory, name))

    matching_source = False
    for path in candidates:
        try:
            with open(path, "r", errors="ignore") as f:
                text = f.read().upper()
        except OSError:
            continue
        if ("SQLITE3_" in text and "OVER" in text and "PRECEDING" in text
                and "FOLLOWING" in text and "JOIN" in text
                and ("SYS/SOCKET.H" in text or "SOCKET(" in text)):
            matching_source = True
            break
    assert matching_source, "No C++ server source containing the required SQLite window query was found"


def expected_smoothed(raw, i):
    start = max(0, i - 1)
    end = min(len(raw), i + 2)
    return round(sum(raw[start:end]) / (end - start), 2)


def signal_from_reference(value):
    with sqlite3.connect("/app/reference.db") as conn:
        rows = conn.execute(
            "SELECT min_val, max_val, signal_name FROM signal_types ORDER BY id"
        ).fetchall()
    matches = [name for low, high, name in rows if low <= value <= high]
    return matches[0] if matches else "unknown"


def test_tcp_server_response():
    """Connect to the TCP server, send REPORT, and validate the JSON response."""
    host = '127.0.0.1'
    port = 8000
    video_raw = decoded_brightness()

    pid = listening_server_pid(port)
    assert pid is not None, "No process is listening on TCP port 8000"
    assert_cpp_sql_server(pid)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((host, port))
    except Exception as e:
        pytest.fail(f"Could not connect to TCP server at {host}:{port}: {e}")

    try:
        s.sendall(b"REPORT\n")
        response_data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response_data += chunk
    except Exception as e:
        pytest.fail(f"Error communicating with TCP server: {e}")
    finally:
        s.close()

    assert response_data, "Server returned an empty response."

    try:
        results = json.loads(response_data.decode('utf-8'))
    except json.JSONDecodeError as e:
        pytest.fail(f"Server response is not valid JSON: {e}\nResponse was: {response_data}")

    assert isinstance(results, list), "JSON response must be an array."
    assert len(results) == 10, f"Expected 10 frames in the result, got {len(results)}."

    raw_brightness_list = []
    for i, row in enumerate(results):
        assert "frame" in row, f"Missing 'frame' in row {i}"
        assert "raw_brightness" in row, f"Missing 'raw_brightness' in row {i}"
        assert "smoothed_brightness" in row, f"Missing 'smoothed_brightness' in row {i}"
        assert "signal_name" in row, f"Missing 'signal_name' in row {i}"
        assert row["frame"] == i + 1, f"Expected frame {i+1}, got {row['frame']}"
        assert isinstance(row["raw_brightness"], (int, float)) and not isinstance(row["raw_brightness"], bool)
        assert math.isfinite(row["raw_brightness"])
        assert abs(row["raw_brightness"] - video_raw[i]) <= 1.0, \
            f"Frame {i+1}: raw brightness does not match decoded video ({video_raw[i]:.4f})"
        raw_brightness_list.append(row["raw_brightness"])

    for i, row in enumerate(results):
        window = []
        if i > 0:
            window.append(raw_brightness_list[i-1])
        window.append(raw_brightness_list[i])
        if i < len(raw_brightness_list) - 1:
            window.append(raw_brightness_list[i+1])

        expected_from_response = round(sum(window) / len(window), 2)
        assert abs(row["smoothed_brightness"] - expected_from_response) <= 0.02, \
            f"Frame {row['frame']}: expected smoothed_brightness ~{expected_from_response}, got {row['smoothed_brightness']}"

        expected_from_video = expected_smoothed(video_raw, i)
        assert isinstance(row["smoothed_brightness"], (int, float)) and not isinstance(row["smoothed_brightness"], bool)
        assert math.isfinite(row["smoothed_brightness"])
        assert abs(row["smoothed_brightness"] - expected_from_video) <= 0.03, \
            f"Frame {row['frame']}: smoothing does not match decoded video; expected {expected_from_video}, got {row['smoothed_brightness']}"

        sb = row["smoothed_brightness"]
        if 0.0 <= sb <= 50.0:
            expected_signal = "background"
        elif 50.01 <= sb <= 150.0:
            expected_signal = "low_activity"
        elif 150.01 <= sb <= 255.0:
            expected_signal = "high_activity"
        else:
            expected_signal = "unknown"

        assert row["signal_name"] == expected_signal, \
            f"Frame {row['frame']}: expected signal_name '{expected_signal}' for smoothed brightness {sb}, got '{row['signal_name']}'"
        assert row["signal_name"] == signal_from_reference(expected_from_video), \
            f"Frame {row['frame']}: signal name does not match reference.db mapping"


def test_database_table_exists():
    """Verify that frame_data was created, populated, and contains decoded brightness."""
    db_path = "/app/reference.db"
    video_raw = decoded_brightness()
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='frame_data';")
        table = cursor.fetchone()
        assert table is not None, "Table 'frame_data' does not exist in /app/reference.db."

        cursor.execute("SELECT COUNT(*) FROM frame_data;")
        count = cursor.fetchone()[0]
        assert count == 10, f"Expected 10 rows in frame_data, got {count}."

        cursor.execute("PRAGMA table_info(frame_data);")
        columns = [col[1] for col in cursor.fetchall()]
        assert "frame" in columns or "frame_number" in columns or any("frame" in c.lower() for c in columns), "frame_data table missing a frame column."
        assert "raw_brightness" in columns or "brightness" in columns or any("bright" in c.lower() for c in columns), "frame_data table missing a brightness column."

        frame_col = next((c for c in columns if c in ("frame", "frame_number")),
                         next(c for c in columns if "frame" in c.lower()))
        brightness_col = next((c for c in columns if c in ("raw_brightness", "brightness")),
                              next(c for c in columns if "bright" in c.lower()))
        quote = lambda name: '"' + name.replace('"', '""') + '"'
        cursor.execute(f"SELECT {quote(frame_col)}, {quote(brightness_col)} FROM frame_data ORDER BY {quote(frame_col)}")
        stored = cursor.fetchall()
        assert [row[0] for row in stored] == list(range(1, 11)), "frame_data frame numbers must be 1 through 10"
        for i, (_, brightness) in enumerate(stored):
            assert isinstance(brightness, (int, float)), f"Database brightness for frame {i+1} is not numeric"
            assert abs(brightness - video_raw[i]) <= 1.0, \
                f"Database brightness for frame {i+1} does not match decoded video"

    except sqlite3.Error as e:
        pytest.fail(f"SQLite error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
