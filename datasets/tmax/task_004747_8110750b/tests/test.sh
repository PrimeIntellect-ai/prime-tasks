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
import concurrent.futures
import os
import random
import re
import subprocess
import sys
import time

import pytest
import requests

BASE = "http://127.0.0.1:8080"
API = BASE + "/api/merge"
BACKEND_API = "http://127.0.0.1:8000/api/merge"
APP_DIR = "/app/audio_math_api"
CONFIG = APP_DIR + "/nginx.conf"
TRANSCRIBER = APP_DIR + "/transcriber.py"


def listening_socket_inodes(port, allowed_addresses):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.read().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address, hex_port = local_address.rsplit(":", 1)
            if int(hex_port, 16) == port and state == "0A" and address in allowed_addresses:
                found.add(inode)
    return found


def pids_for_socket_inodes(inodes):
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            pass
    return pids


def process_lineage(pid):
    result = []
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
            with open(f"/proc/{pid}/stat") as f:
                stat = f.read()
            # Everything after the final ')' begins with state followed by ppid.
            ppid = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
        result.append(cmd)
        pid = ppid
    return result


def test_required_nginx_and_flask_are_really_running():
    nginx_inodes = listening_socket_inodes(
        8080,
        {"00000000", "00000000000000000000000000000000"},
    )
    assert nginx_inodes, "Nothing is listening on 0.0.0.0:8080"
    nginx_pids = pids_for_socket_inodes(nginx_inodes)
    assert nginx_pids, "Could not identify the process listening on port 8080"
    assert any(
        any("nginx" in cmd.lower() for cmd in process_lineage(pid))
        for pid in nginx_pids
    ), "Port 8080 is not served by an Nginx process"

    flask_inodes = listening_socket_inodes(8000, {"0100007F"})
    assert flask_inodes, "Nothing is listening on 127.0.0.1:8000"
    flask_pids = pids_for_socket_inodes(flask_inodes)
    assert flask_pids, "Could not identify the process listening on port 8000"
    assert any(
        any(
            ("python" in cmd.lower() and "app.py" in cmd)
            or ("flask" in cmd.lower() and "run" in cmd.lower())
            for cmd in process_lineage(pid)
        )
        for pid in flask_pids
    ), "The backend listener is not a running Flask/Python application"

    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; sys.path.insert(0, '/app/audio_math_api'); "
            "import app, flask; "
            "assert isinstance(app.app, flask.Flask); "
            "assert any(r.rule == '/api/merge' for r in app.app.url_map.iter_rules()); "
            "print('FLASK_APP_OK')",
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert probe.returncode == 0 and "FLASK_APP_OK" in probe.stdout, (
        "app.py does not define the required Flask application and route: "
        + probe.stdout + probe.stderr
    )


def test_nginx_configuration_has_required_proxy_and_rate_limit():
    checked = subprocess.run(
        ["nginx", "-T", "-c", CONFIG, "-p", APP_DIR + "/"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, "nginx configuration is invalid: " + checked.stdout + checked.stderr
    config = checked.stdout + "\n" + checked.stderr

    assert re.search(r"\blisten\s+(?:0\.0\.0\.0:)?8080\s*;", config), "nginx.conf does not listen on port 8080"
    location = re.search(r"location\s+/api/\s*\{([^{}]*)\}", config, re.S)
    assert location, "nginx.conf has no /api/ location"
    body = location.group(1)
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8000\s*;", body), "The /api/ location does not proxy to 127.0.0.1:8000"

    zone = re.search(
        r"limit_req_zone\s+\$binary_remote_addr\s+zone=([A-Za-z0-9_]+):[^;\s]+\s+rate=5r/s\s*;",
        config,
    )
    assert zone, "No valid per-client limit_req_zone with rate=5r/s was found"
    assert re.search(r"limit_req\s+[^;]*\bzone=" + re.escape(zone.group(1)) + r"\b[^;]*;", body), (
        "The 5r/s rate-limit zone is not applied to /api/"
    )


def test_api_merge_endpoint():
    """Test the /api/merge endpoint for correct sorting and merging."""
    params = {"seq": "5,12,1", "file": "test_sequence"}
    try:
        response = requests.get(API, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_result = [1, 5, 8, 12, 19, 42]
    assert "result" in data, "Response JSON missing 'result' key."
    assert data["result"] == expected_result, f"Expected result {expected_result}, got {data['result']}"
    assert set(data) == {"result"}, f"Unexpected JSON fields: {data}"


def test_api_merge_endpoint_different_seq():
    """Test the /api/merge endpoint with a different sequence to ensure mathematical sorting."""
    params = {"seq": "100,2", "file": "test_sequence"}
    try:
        response = requests.get(API, params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    expected_result = [2, 8, 19, 42, 100]
    assert data.get("result") == expected_result, f"Expected mathematically sorted result {expected_result}, got {data.get('result')}"


def test_validation_and_backend_reachability():
    response = requests.get(BACKEND_API, params={"seq": "1"}, timeout=5)
    assert response.status_code == 400, f"Missing file parameter should return 400, got {response.status_code}"
    response = requests.get(API, params={"seq": "1", "file": "does_not_exist"}, timeout=5)
    assert response.status_code == 404, f"Unknown audio file should return 404, got {response.status_code}"


def test_dynamic_transcription_parsing_and_general_integer_merging():
    word_values = [
        ("one", 1), ("two", 2), ("three", 3), ("four", 4),
        ("five", 5), ("six", 6), ("seven", 7), ("eight", 8),
        ("nine", 9), ("ten", 10), ("eleven", 11), ("twelve", 12),
        ("thirteen", 13), ("fourteen", 14), ("fifteen", 15),
        ("sixteen", 16), ("seventeen", 17), ("eighteen", 18),
        ("nineteen", 19), ("twenty", 20), ("thirty", 30),
        ("forty", 40), ("forty two", 42),
    ]
    rng = random.SystemRandom()
    chosen = rng.sample(word_values, 5)
    transcript = ", ".join(word for word, _ in chosen)
    spoken_numbers = [value for _, value in chosen]
    original = open(TRANSCRIBER, "rb").read()

    try:
        with open(TRANSCRIBER, "w") as f:
            f.write("import sys\nprint(" + repr(transcript) + ")\n")

        for _ in range(3):
            seq_numbers = [rng.randint(-250, 500) for _ in range(6)]
            # Include a duplicate to exercise true integer merging rather than set behavior.
            seq_numbers.append(seq_numbers[0])
            seq = ",".join(str(n) for n in seq_numbers)
            response = requests.get(API, params={"seq": seq, "file": "test_sequence"}, timeout=8)
            assert response.status_code == 200, f"Dynamic request failed with {response.status_code}: {response.text}"
            data = response.json()
            expected = sorted(seq_numbers + spoken_numbers)
            assert data == {"result": expected}, f"Expected dynamic result {expected}, got {data}"
            time.sleep(0.25)
    finally:
        with open(TRANSCRIBER, "wb") as f:
            f.write(original)


def test_rate_limiting():
    """Test that Nginx enforces a rate limit of 5 requests per second."""
    time.sleep(3)
    params = {"seq": "1", "file": "test_sequence"}

    def send_one(_):
        try:
            return requests.get(API, params=params, timeout=6).status_code
        except requests.exceptions.RequestException:
            return None

    # A concurrent burst exceeds both the 5r/s rate and any reasonable queue burst.
    with concurrent.futures.ThreadPoolExecutor(max_workers=30) as pool:
        status_codes = [code for code in pool.map(send_one, range(30)) if code is not None]

    # Preserve the original behavioral assertions.
    assert 503 in status_codes, f"Expected rate limiting (HTTP 503) for rapid requests. Got status codes: {status_codes}"
    assert 200 in status_codes, f"Expected at least one successful request. Got status codes: {status_codes}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
