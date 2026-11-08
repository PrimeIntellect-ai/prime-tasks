#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import json
import os
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time

import pytest


def test_siem_ingest_json_exists():
    path = "/home/user/siem_ingest.json"
    assert os.path.exists(path), f"File {path} does not exist. The Go program may not have successfully POSTed to the SIEM endpoint."
    assert os.path.isfile(path), f"{path} is not a regular file."


def test_siem_ingest_content():
    path = "/home/user/siem_ingest.json"
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {path}: {e}")

    assert isinstance(data, list), "The JSON payload should be an array of objects."
    assert len(data) == 3, f"Expected exactly 3 deduplicated error objects, but found {len(data)}."

    expected_objects = [
        {
            "timestamp": "2023-10-12T08:15:00Z",
            "code": "1052",
            "message": "Database connection timeout",
        },
        {
            "timestamp": "2023-10-12T08:17:33Z",
            "code": "2099",
            "message": "User auth failed: invalid token",
        },
        {
            "timestamp": "2023-10-12T08:19:12Z",
            "code": "3001",
            "message": "File not found: /etc/passwd",
        },
    ]

    assert data == expected_objects, "The parsed JSON does not match the expected deduplicated error objects or is in the wrong order."


def _kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        sock = socket.socket()
        try:
            if sock.connect_ex(("127.0.0.1", 8080)) != 0:
                return
        finally:
            sock.close()
        time.sleep(0.1)

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def test_go_program_parses_dynamic_log_and_posts_payload():
    program = "/home/user/process_logs.go"
    assert os.path.exists(program), f"Required Go program {program} does not exist."
    assert os.path.isfile(program), f"{program} is not a regular file."
    assert stat.S_ISREG(os.stat(program).st_mode), f"{program} is not a regular file."

    codes = set()
    while len(codes) < 3:
        codes.add(f"{secrets.randbelow(10000):04d}")
    code1, code2, code3 = list(codes)
    token = secrets.token_hex(12)

    message1 = f'Dynamic "quoted" database event {token}'
    message2 = f"Path failure: /tmp/{token}.dat"
    message3 = f"Final service error {token}"
    raw_log = "\n".join([
        "[2024/02/29 23:59:50] INFO dynamic test started",
        f"[2024/02/29 23:59:58] ERROR [CODE-{code1}] {message1}",
        f"[01 Mar 24 00:00:01 UTC] ERROR [CODE-{code2}] {message2}",
        f"[01 Mar 24 00:00:02 UTC] ERROR [CODE-{code1}] duplicate must be discarded {token}",
        "[2024/03/01 00:30:00] WARNING irrelevant line",
        f"[2024/03/01 01:02:03] ERROR [CODE-{code3}] {message3}",
        f"[2024/03/01 01:03:03] ERROR [CODE-A123] malformed {token}",
        "",
    ])
    expected = [
        {"timestamp": "2024-02-29T23:59:58Z", "code": code1, "message": message1},
        {"timestamp": "2024-03-01T00:00:01Z", "code": code2, "message": message2},
        {"timestamp": "2024-03-01T01:02:03Z", "code": code3, "message": message3},
    ]

    raw_path = "/home/user/raw_server.log"
    ingest_path = "/home/user/siem_ingest.json"
    with open(raw_path, "rb") as f:
        original_raw = f.read()
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(raw_log)
    try:
        os.remove(ingest_path)
    except FileNotFoundError:
        pass

    _kill_port_8080_listeners()
    requests = []

    class CaptureHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            body = self.rfile.read(length)
            requests.append({
                "path": self.path,
                "content_type": self.headers.get("Content-Type", ""),
                "body": body,
            })
            if self.path == "/ingest":
                with open(ingest_path, "wb") as f:
                    f.write(body)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Ingested")
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            pass

    class ReusableHTTPServer(http.server.HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(("127.0.0.1", 8080), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        try:
            result = subprocess.run(
                ["go", "run", program],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=45,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The Go program did not complete within 45 seconds.")
        assert result.returncode == 0, f"go run failed with exit code {result.returncode}: {result.stderr}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        with open(raw_path, "wb") as f:
            f.write(original_raw)

    ingest_requests = [r for r in requests if r["path"] == "/ingest"]
    assert ingest_requests, "The executed Go program did not POST to http://localhost:8080/ingest."

    matching_request = None
    for request in ingest_requests:
        media_type = request["content_type"].split(";", 1)[0].strip().lower()
        if media_type != "application/json":
            continue
        try:
            posted = json.loads(request["body"].decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if posted == expected:
            matching_request = request
            break

    assert matching_request is not None, "No /ingest request used Content-Type application/json with the correctly parsed dynamic payload."
    assert os.path.isfile(ingest_path), "The SIEM endpoint did not receive and save the POST payload."
    with open(ingest_path, "r", encoding="utf-8") as f:
        saved = json.load(f)
    assert saved == expected, "The payload saved by the SIEM endpoint does not match the dynamic log input."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
