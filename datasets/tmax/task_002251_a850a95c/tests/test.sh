#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import urllib.request
import urllib.error
import subprocess
import tempfile
import pytest


def test_deployment_health():
    """Verify that Nginx, Flask, and Redis are correctly wired up and healthy."""
    url = "http://127.0.0.1:8080/api/health"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode("utf-8"))
            assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
            assert data.get("redis") == "connected", f"Expected redis 'connected', got {data.get('redis')}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    except json.JSONDecodeError:
        pytest.fail("Response from health endpoint was not valid JSON.")


def test_symlink_updated():
    """Verify the symlink points to v2."""
    current_link = "/home/user/deploy/current"
    assert os.path.islink(current_link), f"{current_link} is not a symlink."
    target = os.readlink(current_link)
    assert target.endswith("v2") or target == "/home/user/deploy/v2", f"Symlink points to {target}, expected /home/user/deploy/v2"


def test_start_script_env_var():
    """Verify the start script exports REDIS_HOST."""
    start_script = "/home/user/deploy/current/start.sh"
    assert os.path.isfile(start_script), f"Start script {start_script} not found."
    with open(start_script, "r") as f:
        content = f.read()
    assert "REDIS_HOST=127.0.0.1" in content or "export REDIS_HOST" in content, "REDIS_HOST environment variable is not exported in start.sh"


def run_detector(script_path, payload, filename):
    with tempfile.TemporaryDirectory(prefix="waf_cases_") as directory:
        path = os.path.join(directory, filename)
        with open(path, "w", encoding="utf-8") as f:
            f.write(payload)
        result = subprocess.run(
            ["python3", script_path, path], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, f"Detector failed for {filename}: {result.stderr}"
        return result.stdout.strip()


def test_waf_detector_corpus():
    """Exercise the detector on generated paths and independently defined payloads."""
    script_path = "/home/user/waf_detector.py"
    assert os.path.isfile(script_path), f"WAF detector script {script_path} not found."

    cases = [
        ("ordinary_request.dat", "GET /api/items?page=2 HTTP/1.1\nHost: example.test\nUser-Agent: browser\n\n", "CLEAN"),
        ("notes_evil_named_but_safe.dat", "POST /api/comment HTTP/1.1\nContent-Type: text/plain\n\nA normal comment about selecting one item.", "CLEAN"),
        ("friendly_clean_name.dat", "GET /download?name=..%s..%svar%slog HTTP/1.1\nHost: example.test\n\n" % ("/", "/", "/"), "EVIL"),
        ("request_a.dat", "POST /login HTTP/1.1\nHost: example.test\n\nusername=admin%27%20oR%201%3D1", "EVIL"),
        ("request_b.dat", "GET /search?q=uNiOn%20SeLeCt%20password%20FROM%20users HTTP/1.1\nHost: example.test\n\n", "EVIL"),
        ("request_c.dat", "POST /profile HTTP/1.1\nHost: example.test\n\nname=<ScRiPt>alert(7)</sCrIpT>", "EVIL"),
    ]
    for filename, payload, expected in cases:
        output = run_detector(script_path, payload, filename)
        assert output == expected, f"Expected {expected} for {filename}, got {output!r}"


def test_monitor_logs_script_and_cron():
    """Verify the monitor extracts only IPs associated with 403/500 and cron appends it."""
    script_path = "/home/user/monitor_logs.sh"
    log_path = "/home/user/nginx/access.log"
    assert os.path.isfile(script_path), f"Log monitoring script {script_path} not found."
    assert os.access(script_path, os.X_OK), f"Log monitoring script {script_path} is not executable."

    original = None
    existed = os.path.exists(log_path)
    if existed:
        with open(log_path, "rb") as f:
            original = f.read()
    test_log = (
        '198.51.100.23 - - [10/Oct/2025:10:00:00 +0000] "GET /ok HTTP/1.1" 200 12\n'
        '203.0.113.44 - - [10/Oct/2025:10:00:01 +0000] "GET /blocked HTTP/1.1" 403 0\n'
        '192.0.2.77 - - [10/Oct/2025:10:00:02 +0000] "POST /api HTTP/1.1" 500 4\n'
        '198.51.100.99 - - [10/Oct/2025:10:00:03 +0000] "GET /missing HTTP/1.1" 404 0\n'
    )
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(test_log)
        result = subprocess.run([script_path], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"Monitor script failed: {result.stderr}"
        output_tokens = result.stdout.split()
        assert output_tokens.count("203.0.113.44") == 1, "Did not extract the IP for a 403 response exactly once."
        assert output_tokens.count("192.0.2.77") == 1, "Did not extract the IP for a 500 response exactly once."
        assert "198.51.100.23" not in output_tokens, "Extracted an IP associated only with status 200."
        assert "198.51.100.99" not in output_tokens, "Extracted an IP associated only with status 404."
    finally:
        if existed:
            with open(log_path, "wb") as f:
                f.write(original)
        elif os.path.exists(log_path):
            os.remove(log_path)

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."
    active = [line.strip() for line in result.stdout.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    matching = [line for line in active if "monitor_logs.sh" in line and "suspicious_ips.txt" in line]
    assert matching, "No active cron entry runs monitor_logs.sh and writes suspicious_ips.txt."
    fields = matching[0].split()
    assert len(fields) >= 6 and fields[0] == "*/5", "Cron job is not scheduled every 5 minutes."
    assert ">>" in matching[0], "Cron job must append (>>) output to suspicious_ips.txt."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
