#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave

import numpy as np
import pytest
import scipy.io.wavfile as wavfile

HEALTH_SCRIPT = "/home/user/health_service.py"
NORMALIZE_SCRIPT = "/home/user/normalize.py"
VERIFY_SCRIPT = "/home/user/verify.sh"
LOG_PATH = "/home/user/health_status.log"


def fetch(url, timeout=2):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.getcode(), response.read().decode("utf-8").strip()


def wait_for_response(url, expected=None, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            status, body = fetch(url, timeout=0.5)
            if status == 200 and (expected is None or body == expected):
                return status, body
            last_error = AssertionError(f"Unexpected response: {status} {body!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Service at {url} did not become ready: {last_error}")


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local_port = fields[1].rsplit(":", 1)[1].upper()
                        if local_port == wanted:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pids(port):
    inodes = listener_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def stop_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    assert not listener_inodes(port), f"Could not free TCP port {port}"


def start_health_script():
    proc = subprocess.Popen(
        [sys.executable, HEALTH_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_response("http://127.0.0.1:9090/health", "MIGRATION_READY")
    except Exception:
        if proc.poll() is None:
            proc.terminate()
        raise
    return proc


def run_verify_and_read_log():
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    subprocess.run(["bash", VERIFY_SCRIPT], cwd="/home/user", timeout=10, check=True)
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing after running verify.sh"
    with open(LOG_PATH, "r") as f:
        return f.read().strip()


def test_audio_normalization_mse():
    """Retain the original fixture/ground-truth normalization check."""
    original_path = "/app/ivr_greeting.wav"
    processed_path = "/home/user/processed_greeting.wav"

    assert os.path.exists(original_path), f"Original audio file {original_path} is missing."
    assert os.path.exists(processed_path), f"Processed audio file {processed_path} is missing."

    rate_orig, data_orig = wavfile.read(original_path)
    data_orig = data_orig.astype(np.float64)

    peak = np.max(np.abs(data_orig))
    if peak == 0:
        target_data = data_orig
    else:
        scaling_factor = 26214.0 / peak
        target_data = np.round(data_orig * scaling_factor).astype(np.int16)

    rate_proc, data_proc = wavfile.read(processed_path)

    assert rate_orig == rate_proc, f"Sample rate mismatch: original {rate_orig}, processed {rate_proc}"
    assert len(target_data) == len(data_proc), f"Length mismatch: expected {len(target_data)}, got {len(data_proc)}"

    mse = np.mean((target_data.astype(np.float64) - data_proc.astype(np.float64)) ** 2)
    assert mse <= 2.0, f"MSE is too high: {mse} (threshold is 2.0)"


def test_normalize_script_exists_and_processes_new_input():
    assert os.path.isfile(NORMALIZE_SCRIPT), f"{NORMALIZE_SCRIPT} is missing or is not a regular file"

    source = np.array([-7000, -321, 0, 1234, 9999, -9999, 5000], dtype=np.int16)
    expected = np.round(source.astype(np.float64) * (26214.0 / 9999.0)).astype(np.int16)

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.wav")
        output_path = os.path.join(td, "output.wav")
        wavfile.write(input_path, 11025, source)
        subprocess.run(
            [sys.executable, NORMALIZE_SCRIPT, input_path, output_path],
            timeout=10,
            check=True,
        )
        assert os.path.isfile(output_path), "normalize.py did not create its requested output"

        with wave.open(output_path, "rb") as output_wave:
            assert output_wave.getnchannels() == 1, "Normalized output is not mono"
            assert output_wave.getsampwidth() == 2, "Normalized output is not 16-bit PCM"
            assert output_wave.getcomptype() == "NONE", "Normalized output is compressed"
            assert output_wave.getframerate() == 11025, "normalize.py changed the sample rate"

        rate, actual = wavfile.read(output_path)
        assert rate == 11025
        assert actual.dtype == np.int16, f"Expected int16 output, got {actual.dtype}"
        assert actual.shape == source.shape
        mse = np.mean((expected.astype(np.float64) - actual.astype(np.float64)) ** 2)
        assert mse <= 2.0, f"normalize.py failed a fresh input; MSE was {mse}"
        assert np.max(np.abs(actual.astype(np.int32))) == 26214


def test_health_status_log():
    """Retain the original generated-log check."""
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "MIGRATION_READY", f"Expected log content 'MIGRATION_READY', got '{content}'"


def test_health_service_running_on_9090():
    """Retain the original direct health-service check."""
    url = "http://127.0.0.1:9090/health"
    try:
        status, body = fetch(url)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to health service at {url}: {e}")
    assert status == 200, f"Expected HTTP 200 from {url}, got {status}"
    assert body == "MIGRATION_READY", f"Expected response 'MIGRATION_READY' from {url}, got '{body}'"


def test_submitted_health_service_and_real_forwarding_and_verify_script():
    assert os.path.isfile(HEALTH_SCRIPT), f"{HEALTH_SCRIPT} is missing or is not a regular file"
    assert os.path.isfile(VERIFY_SCRIPT), f"{VERIFY_SCRIPT} is missing or is not a regular file"
    with open(VERIFY_SCRIPT, "r", errors="replace") as f:
        verify_source = f.read()
    assert "curl" in verify_source, "verify.sh must use curl as requested"

    # Remove any pre-existing backend, then execute the submitted service itself.
    stop_listeners(9090)
    health_proc = start_health_script()
    assert health_proc.poll() is None, "health_service.py exited instead of running the service"

    # Replace the backend with a verifier-controlled nonce service. Seeing the nonce
    # on 8080 proves that 8080 is forwarding to 9090 rather than serving independently.
    stop_listeners(9090)
    nonce = "FORWARD_PROBE_7d3c91"
    nonce_code = f'''\
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = {nonce!r}.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 9090), H).serve_forever()
'''
    nonce_proc = subprocess.Popen(
        [sys.executable, "-c", nonce_code],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_response("http://127.0.0.1:9090/health", nonce)
        status, body = wait_for_response("http://127.0.0.1:8080/health", nonce)
        assert status == 200
        assert body == nonce, "Port 8080 is not forwarding responses from port 9090"

        logged = run_verify_and_read_log()
        assert logged == nonce, "verify.sh did not fetch the live response through port 8080"
    finally:
        if nonce_proc.poll() is None:
            nonce_proc.terminate()
            try:
                nonce_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                nonce_proc.kill()
        stop_listeners(9090)

    # Restore the requested final state using the submitted service, then execute
    # verify.sh once more so its required final log remains in place.
    restored_proc = start_health_script()
    assert restored_proc.poll() is None
    logged = run_verify_and_read_log()
    assert logged == "MIGRATION_READY", f"Expected final log content MIGRATION_READY, got {logged!r}"


def test_port_forwarding_on_8080():
    """Retain the original final forwarding check."""
    url = "http://127.0.0.1:8080/health"
    try:
        status, body = fetch(url)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to forwarded port at {url}: {e}")
    assert status == 200, f"Expected HTTP 200 from {url}, got {status}"
    assert body == "MIGRATION_READY", f"Expected response 'MIGRATION_READY' from {url}, got '{body}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
