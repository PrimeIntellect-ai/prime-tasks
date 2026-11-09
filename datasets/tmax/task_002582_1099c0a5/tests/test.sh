#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import signal
import socket
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

BINARY = "/app/bin/extractor"
CONFIG = "/app/config/pipeline.json"
URL = "http://127.0.0.1:8080/analyze"


def test_01_extractor_binary_exists_executable_and_matches_o3_build():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable"

    reference_source = r'''#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <wav_file>\n", argv[0]);
        return 1;
    }
    // Simulate audio extraction
    // In a real scenario, this would parse the audio fixture
    printf("DURATION=12|TRANSCRIPT=PIPELINE_OK_992\n");
    return 0;
}
'''
    source_path = "/tmp/reference_extractor.c"
    reference_binary = "/tmp/reference_extractor"
    with open(source_path, "w") as f:
        f.write(reference_source)
    subprocess.run(
        ["gcc", "-O3", source_path, "-o", reference_binary],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    subprocess.run(["objcopy", "--dump-section", ".text=/tmp/submitted.text", BINARY], check=True)
    subprocess.run(["objcopy", "--dump-section", ".text=/tmp/reference.text", reference_binary], check=True)
    with open("/tmp/submitted.text", "rb") as f:
        submitted_text = f.read()
    with open("/tmp/reference.text", "rb") as f:
        reference_text = f.read()
    assert submitted_text == reference_text, "extractor code does not match the supplied source compiled with -O3"

    no_arg = subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert no_arg.returncode != 0
    run = subprocess.run([BINARY, "/app/ci_diagnostic.wav"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert run.returncode == 0
    assert run.stdout.strip() == "DURATION=12|TRANSCRIPT=PIPELINE_OK_992"


def test_02_config_json_content():
    assert os.path.isfile(CONFIG), f"{CONFIG} does not exist"
    with open(CONFIG, "r") as f:
        try:
            config_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {CONFIG} as JSON")
    expected = {"max_duration_seconds": 300, "require_stego": True, "strict_mode": 1}
    assert config_data == expected, f"{CONFIG} content does not match expected structure"


def test_03_existing_benchmark_results():
    results_path = "/app/benchmark_results.json"
    assert os.path.isfile(results_path), f"{results_path} does not exist"
    with open(results_path, "r") as f:
        try:
            results_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {results_path} as JSON")
    assert "average_latency_ms" in results_data
    value = results_data["average_latency_ms"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool)
    assert math.isfinite(value) and value >= 0


def _install_test_extractor(duration, transcript, marker):
    temporary = BINARY + ".verifier_tmp"
    script = f'''#!/bin/sh
if [ "$#" -ne 1 ] || [ "$1" != "/app/ci_diagnostic.wav" ]; then
    exit 73
fi
printf executed > {marker!r}
printf '%s\\n' 'DURATION={duration}|TRANSCRIPT={transcript}'
'''
    with open(temporary, "w") as f:
        f.write(script)
    os.chmod(temporary, 0o755)
    os.replace(temporary, BINARY)


def test_04_api_executes_extractor_parses_output_and_enforces_constraint():
    try:
        response = requests.post(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")
    assert response.status_code == 200
    assert response.json() == {"status": "success", "duration": 12, "transcript": "PIPELINE_OK_992"}

    backup = "/tmp/original_extractor"
    with open(BINARY, "rb") as src, open(backup, "wb") as dst:
        dst.write(src.read())
    os.chmod(backup, 0o755)

    try:
        token = uuid.uuid4().hex
        duration = 20 + (int(token[:4], 16) % 250)
        transcript = "DYNAMIC_" + token
        marker = "/tmp/extractor_marker_" + token
        _install_test_extractor(duration, transcript, marker)
        response = requests.post(URL, timeout=5)
        assert response.status_code == 200
        assert response.json() == {
            "status": "success",
            "duration": duration,
            "transcript": transcript,
        }
        assert os.path.isfile(marker), "API did not execute /app/bin/extractor"

        token2 = uuid.uuid4().hex
        marker2 = "/tmp/extractor_marker_" + token2
        _install_test_extractor(301, "TOO_LONG_" + token2, marker2)
        response = requests.post(URL, timeout=5)
        assert response.status_code == 400
        assert response.json() == {"status": "error", "message": "Constraint violated"}
        assert os.path.isfile(marker2), "API did not execute extractor for the constraint test"
    finally:
        os.replace(backup, BINARY)
        os.chmod(BINARY, 0o755)


def _listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def _stop_service_on_8080():
    deadline = time.time() + 5
    while time.time() < deadline:
        pids = _listener_pids(8080)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.15)
    assert not _listener_pids(8080), "Could not stop the API server for benchmark verification"


def test_05_benchmark_script_makes_50_sequential_posts_and_writes_result():
    benchmark = "/app/benchmark.py"
    results = "/app/benchmark_results.json"
    assert os.path.isfile(benchmark), f"{benchmark} does not exist"
    _stop_service_on_8080()

    state = {"count": 0, "active": 0, "max_active": 0}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            with lock:
                state["count"] += 1
                state["active"] += 1
                state["max_active"] = max(state["max_active"], state["active"])
            try:
                time.sleep(0.02)
                body = b'{"status":"success","duration":12,"transcript":"PIPELINE_OK_992"}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            finally:
                with lock:
                    state["active"] -= 1

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        if os.path.exists(results):
            os.unlink(results)
        completed = subprocess.run(
            ["python3", benchmark],
            cwd="/app",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert completed.returncode == 0, completed.stderr
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert state["count"] == 50, f"benchmark sent {state['count']} POST requests instead of 50"
    assert state["max_active"] == 1, "benchmark requests were not sequential"
    assert os.path.isfile(results), "benchmark did not create benchmark_results.json"
    with open(results) as f:
        data = json.load(f)
    assert set(data) == {"average_latency_ms"}
    value = data["average_latency_ms"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool)
    assert math.isfinite(value) and value >= 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
