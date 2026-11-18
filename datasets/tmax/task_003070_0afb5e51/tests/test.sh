#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import secrets
import signal
import socketserver
import stat
import subprocess
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler
from pathlib import Path

OUTPUT_PATH = "/home/user/processed_logs.jsonl"
MODULE_PATH = Path("/home/user/log_processor")


def test_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."


def test_output_file_content_and_format():
    if not os.path.exists(OUTPUT_PATH):
        return  # Handled by test_output_file_exists

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content, f"The output file {OUTPUT_PATH} is empty."
    lines = content.split('\n')

    assert len(lines) == 5, f"Expected exactly 5 lines in the output file, got {len(lines)}."

    expected_data = [
        {"timestamp": "2023-10-01T10:00:00.000Z", "message": "System startup."},
        {"timestamp": "2023-10-01T10:00:01.000Z", "message": "CPU temp is high: 95°C."},
        {"timestamp": "2023-10-01T10:00:02.000Z", "message": "Warning: fan speed – critical!"},
        {"timestamp": "2023-10-01T10:00:03.000Z", "message": "System stabilized."},
        {"timestamp": "2023-10-01T10:00:04.000Z", "message": "User ä logged in."}
    ]

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} is not valid JSON: {line}"

        assert "timestamp" in data, f"Line {i+1} missing 'timestamp' key."
        assert "message" in data, f"Line {i+1} missing 'message' key."
        assert len(data.keys()) == 2, f"Line {i+1} has incorrect number of keys: {list(data.keys())}. Expected exactly 'timestamp' and 'message'."

        actual_ts = data["timestamp"]
        expected_ts = expected_data[i]["timestamp"]
        assert actual_ts == expected_ts, f"Line {i+1} has incorrect timestamp. Expected '{expected_ts}', got '{actual_ts}'."

        actual_msg = data["message"]
        expected_msg = expected_data[i]["message"]
        assert actual_msg == expected_msg, f"Line {i+1} has incorrect message. Expected '{expected_msg}', got '{actual_msg}'."

        # Verify Unicode Normalization Form C (NFC)
        assert unicodedata.is_normalized('NFC', actual_msg), f"Line {i+1} message is not NFC normalized."


def _kill_port_8080_users():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    victims.add(int(proc.name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class _ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


class _RawLogHandler(BaseHTTPRequestHandler):
    payload = b""
    request_count = 0

    def do_GET(self):
        if self.path != "/raw.log":
            self.send_error(404)
            return
        type(self).request_count += 1
        body = type(self).payload
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def _format_timestamp(value):
    return value.strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"


def _parse_timestamp(value):
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=datetime.timezone.utc)


def _decode_message(raw):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1252")
    return unicodedata.normalize("NFC", text)


def _make_payload_and_expected(records):
    payload_lines = []
    timestamps = []
    for timestamp, message in records:
        marker = timestamp if timestamp is not None else "???"
        payload_lines.append(b"[" + marker.encode("ascii") + b"] " + message)
        timestamps.append(_parse_timestamp(timestamp) if timestamp is not None else None)

    i = 0
    while i < len(timestamps):
        if timestamps[i] is not None:
            i += 1
            continue
        left = i - 1
        right = i
        while right < len(timestamps) and timestamps[right] is None:
            right += 1
        assert left >= 0 and right < len(timestamps)
        gap = right - left
        total_us = int((timestamps[right] - timestamps[left]).total_seconds() * 1_000_000)
        assert total_us % gap == 0
        step = datetime.timedelta(microseconds=total_us // gap)
        for position in range(left + 1, right):
            timestamps[position] = timestamps[left] + step * (position - left)
        i = right + 1

    expected = [
        {"timestamp": _format_timestamp(timestamps[index]), "message": _decode_message(message)}
        for index, (_, message) in enumerate(records)
    ]
    return b"\n".join(payload_lines) + b"\n", expected


def _check_dynamic_output(expected):
    assert os.path.isfile(OUTPUT_PATH), "The Go program did not create processed_logs.jsonl."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content, "The Go program created an empty output file."
    lines = content.split("\n")
    assert len(lines) == len(expected), f"Expected {len(expected)} output lines, got {len(lines)}."
    for index, line in enumerate(lines):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Dynamic output line {index + 1} is invalid JSON: {line}") from exc
        assert set(actual.keys()) == {"timestamp", "message"}, f"Dynamic output line {index + 1} must have exactly timestamp and message keys."
        assert actual == expected[index], f"Dynamic output line {index + 1} is incorrect: expected {expected[index]!r}, got {actual!r}."
        assert unicodedata.is_normalized("NFC", actual["message"]), f"Dynamic output line {index + 1} is not NFC normalized."


def test_go_program_fetches_and_processes_unseen_inputs():
    assert MODULE_PATH.is_dir(), f"Required Go module directory {MODULE_PATH} does not exist."
    go_mod = MODULE_PATH / "go.mod"
    assert go_mod.exists() and stat.S_ISREG(go_mod.stat().st_mode), f"{go_mod} is not a regular file."
    go_sources = [p for p in MODULE_PATH.rglob("*.go") if p.is_file()]
    assert go_sources, f"No Go source files were found under {MODULE_PATH}."

    token = secrets.token_hex(12)
    base1 = datetime.datetime(2025, 2, 3, 4, 5, 6, tzinfo=datetime.timezone.utc)
    records1 = [
        (_format_timestamp(base1), f"Start {token}: Cafe\u0301".encode("utf-8")),
        (None, b"Legacy \x93quote\x94 costs \x8010 " + token.encode("ascii")),
        (None, f"Middle {token} plain UTF-8".encode("utf-8")),
        (None, f"User a\u0308 {token}".encode("utf-8")),
        (_format_timestamp(base1 + datetime.timedelta(seconds=4)), f"End {token}".encode("utf-8")),
    ]

    base2 = datetime.datetime(2026, 7, 8, 9, 10, 11, 125000, tzinfo=datetime.timezone.utc)
    records2 = [
        (_format_timestamp(base2), f"Second start {token}".encode("utf-8")),
        (None, b"CP1252 dash \x96 " + token.encode("ascii")),
        (None, f"Combining n\u0303 {token}".encode("utf-8")),
        (_format_timestamp(base2 + datetime.timedelta(milliseconds=1500)), f"Anchor {token}".encode("utf-8")),
        (None, b"Price \xa312 " + token.encode("ascii")),
        (_format_timestamp(base2 + datetime.timedelta(milliseconds=2500)), f"Final {token}".encode("utf-8")),
    ]

    cases = [_make_payload_and_expected(records1), _make_payload_and_expected(records2)]
    _kill_port_8080_users()
    server = _ReusableTCPServer(("127.0.0.1", 8080), _RawLogHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for payload, expected in cases:
            _RawLogHandler.payload = payload
            _RawLogHandler.request_count = 0
            try:
                os.remove(OUTPUT_PATH)
            except FileNotFoundError:
                pass
            result = subprocess.run(
                ["go", "run", "."],
                cwd=str(MODULE_PATH),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=60,
            )
            assert result.returncode == 0, f"go run . failed with exit code {result.returncode}:\n{result.stdout}"
            assert _RawLogHandler.request_count > 0, "The Go program did not fetch http://127.0.0.1:8080/raw.log."
            _check_dynamic_output(expected)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
