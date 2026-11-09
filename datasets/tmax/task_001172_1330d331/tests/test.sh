#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

import pytest


def test_audio_processor_service_running_enabled_and_network_ordered():
    result = subprocess.run(
        ["systemctl", "--user", "is-active", "audio-processor.service"],
        capture_output=True, text=True, check=False
    )
    assert result.stdout.strip() == "active", "Service audio-processor.service is not active."

    enabled = subprocess.run(
        ["systemctl", "--user", "is-enabled", "audio-processor.service"],
        capture_output=True, text=True, check=False
    )
    assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", \
        "Service audio-processor.service is not enabled."

    after = subprocess.run(
        ["systemctl", "--user", "show", "audio-processor.service", "-p", "After", "--value"],
        capture_output=True, text=True, check=False
    )
    wants = subprocess.run(
        ["systemctl", "--user", "show", "audio-processor.service", "-p", "Wants", "--value"],
        capture_output=True, text=True, check=False
    )
    requires = subprocess.run(
        ["systemctl", "--user", "show", "audio-processor.service", "-p", "Requires", "--value"],
        capture_output=True, text=True, check=False
    )
    assert after.returncode == 0 and "network-online.target" in after.stdout.split(), \
        "Service is not ordered after network-online.target."
    dependencies = wants.stdout.split() + requires.stdout.split()
    assert "network-online.target" in dependencies, \
        "Service does not request network-online.target."


def test_audio_duration_file():
    duration_file = Path("/home/user/audio_duration.txt")
    assert duration_file.exists(), f"Duration file missing at {duration_file}"
    content = duration_file.read_text().strip()
    assert content == "12.45", f"Expected duration '12.45', got '{content}'"


def test_cron_job_exists():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=False)
    crontab_content = result.stdout
    assert "/home/user/monitor_storage.sh" in crontab_content, \
        "monitor_storage.sh not found in crontab"
    lines = [line for line in crontab_content.splitlines()
             if "/home/user/monitor_storage.sh" in line and not line.strip().startswith("#")]
    assert lines, "No active cron job found for monitor_storage.sh"
    parts = lines[0].strip().split()
    assert parts[0] == "*/5", f"Expected '*/5' for minute field, got '{parts[0]}'"


def test_monitor_storage_script_behavior():
    script = Path("/home/user/monitor_storage.sh")
    archive = Path("/home/user/audio_archive")
    alert_log = Path("/home/user/storage_alerts.log")
    assert script.exists(), f"Script missing at {script}"
    assert os.access(script, os.X_OK), f"Script at {script} is not executable"

    temp_root = Path(tempfile.mkdtemp(prefix="storage-verifier-"))
    saved_archive = temp_root / "saved_archive"
    saved_log = temp_root / "saved_log"
    had_log = alert_log.exists()

    archive.rename(saved_archive)
    archive.mkdir()
    if had_log:
        alert_log.rename(saved_log)

    sentinel = "VERIFIER_SENTINEL_" + uuid.uuid4().hex
    try:
        alert_log.write_text(sentinel + "\n")

        # An archive below the threshold must not produce an alert.
        (archive / "small.bin").write_bytes(os.urandom(1024 * 1024))
        subprocess.run([str(script)], check=True, timeout=20)
        assert alert_log.read_text() == sentinel + "\n", \
            "Storage monitor logged QUOTA_EXCEEDED below 50MB."

        # Replace it with allocated data exceeding 50MB.
        (archive / "small.bin").unlink()
        with (archive / "large.bin").open("wb") as f:
            block = b"X" * (1024 * 1024)
            for _ in range(52):
                f.write(block)

        before = int(time.time())
        subprocess.run([str(script)], check=True, timeout=20)
        after = int(time.time())
        lines = alert_log.read_text().splitlines()
        assert lines and lines[0] == sentinel, "Storage monitor overwrote the existing log."
        alerts = [line for line in lines[1:] if "QUOTA_EXCEEDED" in line]
        assert alerts, "Storage monitor did not log QUOTA_EXCEEDED above 50MB."

        line = alerts[-1]
        assert line.strip() != "QUOTA_EXCEEDED", "Storage alert is missing a timestamp."
        current_year = str(datetime.datetime.now().year)
        epoch_values = [int(v) for v in re.findall(r"(?<!\d)\d{10}(?!\d)", line)]
        assert current_year in line or any(before - 120 <= value <= after + 120 for value in epoch_values), \
            "Storage alert does not contain a current timestamp."
    finally:
        shutil.rmtree(archive, ignore_errors=True)
        saved_archive.rename(archive)
        if alert_log.exists():
            alert_log.unlink()
        if had_log:
            saved_log.rename(alert_log)
        shutil.rmtree(temp_root, ignore_errors=True)


def run_sanitizer(script, path):
    return subprocess.run(["python3", str(script), str(path)], timeout=10).returncode


def test_sanitize_config_adversarial_corpus_and_generated_inputs():
    script = Path("/home/user/sanitize_config.py")
    assert script.exists(), f"Sanitize script missing at {script}"
    assert os.access(script, os.X_OK), f"Sanitize script at {script} is not executable"

    clean_dir = Path("/app/corpus/clean")
    evil_dir = Path("/app/corpus/evil")
    clean_failed = []
    evil_failed = []

    if clean_dir.exists():
        for f in clean_dir.iterdir():
            if f.is_file() and run_sanitizer(script, f) != 0:
                clean_failed.append(f.name)
    if evil_dir.exists():
        for f in evil_dir.iterdir():
            if f.is_file() and run_sanitizer(script, f) != 1:
                evil_failed.append(f.name)

    assert not clean_failed, f"Clean corpus files rejected: {', '.join(clean_failed)}"
    assert not evil_failed, f"Evil corpus files bypassed: {', '.join(evil_failed)}"

    nonce = uuid.uuid4().hex
    generated = {
        "clean_plain": (f"name: {nonce}\npath: /var/tmp/{nonce}.log\nprice: $5\n", 0),
        "clean_parentheses": (f"description: audio ({nonce})\n", 0),
        "evil_dollar_substitution": (f"value: prefix$(printf {nonce})suffix\n", 1),
        "evil_backticks": (f"value: before`printf {nonce}`after\n", 1),
        "evil_passwd": (f"source: /etc/passwd?marker={nonce}\n", 1),
        "evil_shadow": (f"source: prefix-/etc/shadow-{nonce}\n", 1),
    }
    with tempfile.TemporaryDirectory(prefix="sanitizer-verifier-") as td:
        for name, (content, expected) in generated.items():
            path = Path(td) / name
            path.write_text(content)
            actual = run_sanitizer(script, path)
            assert actual == expected, f"Sanitizer returned {actual} for generated case {name}; expected {expected}."


class DummyBackendHandler(BaseHTTPRequestHandler):
    token = ""
    dynamic_path = ""
    seen_paths = []
    seen_marker = None

    def do_GET(self):
        type(self).seen_paths.append(self.path)
        type(self).seen_marker = self.headers.get("X-Verifier-Marker")
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        if self.path == "/":
            self.wfile.write(b"BACKEND_SUCCESS")
        else:
            self.wfile.write(("DYNAMIC_BACKEND_" + type(self).token + "_" + self.path).encode())

    def log_message(self, format, *args):
        pass


def test_reverse_proxy_forwards_to_backend():
    proxy = Path("/home/user/proxy.py")
    assert proxy.exists(), f"Proxy script missing at {proxy}"
    assert os.access(proxy, os.X_OK), f"Proxy script at {proxy} is not executable"

    token = uuid.uuid4().hex
    marker = uuid.uuid4().hex
    dynamic_path = "/verify/" + uuid.uuid4().hex + "?q=" + uuid.uuid4().hex
    DummyBackendHandler.token = token
    DummyBackendHandler.dynamic_path = dynamic_path
    DummyBackendHandler.seen_paths = []
    DummyBackendHandler.seen_marker = None

    server = HTTPServer(("127.0.0.1", 9090), DummyBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        time.sleep(1)

        # Retain the original expected backend response assertion.
        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=5) as response:
            body = response.read().decode("utf-8")
            assert body == "BACKEND_SUCCESS", "Proxy did not return expected response from backend"

        request = urllib.request.Request(
            "http://127.0.0.1:8080" + dynamic_path,
            headers={"X-Verifier-Marker": marker},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read().decode("utf-8")
        expected = "DYNAMIC_BACKEND_" + token + "_" + dynamic_path
        assert body == expected, "Proxy did not return the dynamically generated backend response."
        assert dynamic_path in DummyBackendHandler.seen_paths, "Backend did not receive the proxied path and query."
        assert DummyBackendHandler.seen_marker == marker, "Backend did not receive the proxied request headers."
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
