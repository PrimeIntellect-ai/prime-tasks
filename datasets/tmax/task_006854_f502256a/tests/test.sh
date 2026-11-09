#!/bin/bash
set -e
mkdir -p /logs/verifier

# Free the instructed port if the agent left its HTTP server running.
pkill -f '[p]ython.*http.server.*8080' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest


def test_logs_downloaded():
    server_logs = "/home/user/server/logs.txt"
    workspace_logs = "/home/user/workspace/logs.txt"

    assert os.path.isfile(workspace_logs), f"The file {workspace_logs} does not exist. Did you download it?"

    with open(server_logs, 'r') as f:
        server_content = f.read()
    with open(workspace_logs, 'r') as f:
        workspace_content = f.read()

    assert server_content == workspace_content, f"The content of {workspace_logs} does not match {server_logs}."


def test_summary_json_exists_and_correct():
    summary_path = "/home/user/workspace/summary.json"

    assert os.path.isfile(summary_path), f"The file {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {summary_path} is not valid JSON.")

    expected_keys = {"min", "max", "final_rolling_avg"}
    assert set(data.keys()) == expected_keys, f"The JSON keys in {summary_path} do not match the expected keys. Found: {list(data.keys())}"

    assert data["min"] == 8, f"Expected 'min' to be 8, but got {data['min']}."
    assert data["max"] == 35, f"Expected 'max' to be 35, but got {data['max']}."

    # 35, 8, 14 -> average is 19.0
    assert data["final_rolling_avg"] == 19.0, f"Expected 'final_rolling_avg' to be 19.0, but got {data['final_rolling_avg']}."


def _find_agent_scripts():
    candidates = []
    excluded = {os.path.abspath(__file__), "/tmp/test_final_state.py"}

    for root in ("/home/user", "/tmp"):
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if not d.startswith('.') and d not in {"__pycache__"}]
            for filename in filenames:
                path = os.path.abspath(os.path.join(directory, filename))
                if path in excluded or path in {
                    "/home/user/server/logs.txt",
                    "/home/user/workspace/logs.txt",
                    "/home/user/workspace/summary.json",
                }:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        raw = f.read()
                    text = raw.decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue

                is_script = filename.endswith((".py", ".sh")) or text.startswith("#!")
                markers = sum(marker in text for marker in (
                    "localhost:8080", "logs.txt", "summary.json", "Duration"
                ))
                if is_script and markers >= 2:
                    # Prefer downloaders, then analysis scripts.
                    priority = 0 if ("localhost:8080" in text or "http://" in text) else 1
                    candidates.append((priority, path))

    return [path for _, path in sorted(set(candidates))]


def _run_script(path):
    try:
        with open(path, "rb") as f:
            first_line = f.readline().decode("utf-8", errors="ignore")
        if path.endswith(".py") or "python" in first_line:
            command = ["python3", path]
        elif path.endswith(".sh") or "sh" in first_line or os.access(path, os.X_OK):
            command = ["bash", path] if not os.access(path, os.X_OK) else [path]
        else:
            return
        subprocess.run(
            command,
            cwd=os.path.dirname(path) or "/home/user/workspace",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def test_scripts_download_and_compute_dynamic_fixture():
    scripts = _find_agent_scripts()
    assert scripts, "No agent-created download/processing script was found."

    rng = secrets.SystemRandom()
    values = [rng.randint(41, 900) for _ in range(6)]
    while sum(values[-3:]) % 3 == 0:
        values[-1] = rng.randint(41, 900)

    lines = [
        f"[INFO] event-a - Duration: {values[0]}ms - Status: 200",
        "[WARN] ignored-a - Duration: N/Ams - Status: 500",
        f"[INFO] event-b - Duration: {values[1]}ms - Status: 200",
        "[ERROR] ignored-b - Duration: errorms - Status: 400",
        f"[INFO] event-c - Duration: {values[2]}ms - Status: 200",
        f"[INFO] event-d - Duration: {values[3]}ms - Status: 200",
        "[WARN] ignored-c - Duration: 12.5ms - Status: 400",
        f"[INFO] event-e - Duration: {values[4]}ms - Status: 200",
        f"[INFO] event-f - Duration: {values[5]}ms - Status: 200",
    ]
    payload = ("\n".join(lines) + "\n").encode("utf-8")
    expected = {
        "min": min(values),
        "max": max(values),
        "final_rolling_avg": round(sum(values[-3:]) / 3, 2),
    }

    class Handler(BaseHTTPRequestHandler):
        requests = 0

        def do_GET(self):
            if self.path != "/logs.txt":
                self.send_error(404)
                return
            type(self).requests += 1
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    server_path = "/home/user/server/logs.txt"
    workspace_path = "/home/user/workspace/logs.txt"
    summary_path = "/home/user/workspace/summary.json"
    with open(server_path, "rb") as f:
        original_server_data = f.read()

    httpd = None
    try:
        # A decoy on disk ensures the required bytes can only be obtained from HTTP.
        with open(server_path, "wb") as f:
            f.write(b"DECOY: direct copying of the server file is not a download\n")
        for path in (workspace_path, summary_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        httpd = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()

        # Two passes support separate downloader and analyzer scripts regardless of
        # their filenames, while combined scripts normally finish on the first pass.
        for _ in range(2):
            for script in scripts:
                _run_script(script)
                try:
                    with open(workspace_path, "rb") as f:
                        downloaded = f.read()
                    with open(summary_path, "r") as f:
                        current = json.load(f)
                    if downloaded == payload and current == expected:
                        break
                except (OSError, ValueError):
                    continue
            else:
                continue
            break

        assert Handler.requests > 0, "The agent's script did not request /logs.txt over HTTP."
        assert os.path.isfile(workspace_path), "The script did not create the downloaded logs file."
        with open(workspace_path, "rb") as f:
            assert f.read() == payload, "The script did not save the HTTP response as workspace/logs.txt."

        assert os.path.isfile(summary_path), "The script did not create summary.json when executed."
        with open(summary_path, "r") as f:
            data = json.load(f)
        assert set(data.keys()) == {"min", "max", "final_rolling_avg"}
        assert type(data["min"]) is int
        assert type(data["max"]) is int
        assert type(data["final_rolling_avg"]) is float
        assert data == expected, f"Expected dynamically computed summary {expected}, got {data}."
    finally:
        if httpd is not None:
            httpd.shutdown()
            httpd.server_close()
        with open(server_path, "wb") as f:
            f.write(original_server_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
