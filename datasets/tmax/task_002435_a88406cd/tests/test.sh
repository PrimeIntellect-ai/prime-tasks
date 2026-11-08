#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import re
import socket
import tempfile
import threading
import time
import subprocess
import pytest


def test_timezone_file():
    path = "/home/user/timezone.txt"
    assert os.path.isfile(path), f"Missing timezone file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "Pacific/Auckland", f"Expected timezone 'Pacific/Auckland', got '{content}'"


def test_proxy_forwarding():
    received_data = []

    def dummy_backend():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('127.0.0.1', 9090))
            s.listen(1)
            s.settimeout(3)
            conn, _ = s.accept()
            data = conn.recv(1024)
            received_data.append(data)
            conn.close()
            s.close()
        except Exception:
            pass

    t = threading.Thread(target=dummy_backend)
    t.start()
    time.sleep(0.5)

    try:
        c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        c.settimeout(2)
        c.connect(('127.0.0.1', 8080))
        c.sendall(b"proxy_test_payload")
        c.close()
    except Exception as e:
        pytest.fail(f"Could not connect to proxy on port 8080: {e}")

    t.join(timeout=4)
    assert received_data, "No data received on internal backend port 9090. Proxy is not forwarding traffic correctly."
    assert received_data[0] == b"proxy_test_payload", "Data received on port 9090 did not match the payload sent to port 8080."


def run_filter(script_path, data):
    return subprocess.run(
        ["/bin/bash", script_path],
        input=data,
        capture_output=True,
        timeout=3,
    )


def test_bio_filter_adversarial():
    script_path = "/home/user/bio_filter.sh"
    assert os.path.isfile(script_path), f"Missing bio filter script: {script_path}"

    clean_files = glob.glob("/app/clean_bios/*")
    evil_files = glob.glob("/app/evil_bios/*")

    assert len(clean_files) > 0, "Clean corpus missing"
    assert len(evil_files) > 0, "Evil corpus missing"

    clean_failed = []
    for cf in clean_files:
        with open(cf, "rb") as f:
            data = f.read()
        res = run_filter(script_path, data)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        with open(ef, "rb") as f:
            data = f.read()
        res = run_filter(script_path, data)
        if res.returncode == 0:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected (expected exit 0): {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (expected exit 1): {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Additional verification-only cases exercise every stated rule rather than
    # allowing a filter hardcoded to the image's sample corpus.
    clean_cases = [
        f"Profile number {i} enjoys hiking, coding, music! Rating {i}, okay?".encode()
        for i in range(12, 29)
    ]
    clean_cases += [
        b"Letters and numbers 0123456789 are fine.",
        b"Safe punctuation: commas, periods. Questions? Yes!",
        b"A normal biography spread across two lines.\nStill completely ordinary!\n",
        b"My role is moderator, and I enjoy system design.",
    ]

    for i, data in enumerate(clean_cases):
        res = run_filter(script_path, data)
        assert res.returncode == 0, (
            f"Generated clean bio {i} was rejected with status {res.returncode}"
        )

    malicious_cases = []
    for i, metachar in enumerate((b"|", b";", b">", b"<", b"$", b"`")):
        malicious_cases.append(
            b"Ordinary profile " + str(700 + i).encode() + b" contains " + metachar + b" hidden text."
        )
    malicious_cases += [
        b"ADMIN",
        b"AdMiN",
        b"My role is admin.",
        b"Please contact the aDmIn today!",
        b"First line is harmless.\nSecond line mentions ADMIN.\n",
    ]

    for i, data in enumerate(malicious_cases):
        res = run_filter(script_path, data)
        assert res.returncode == 1, (
            f"Generated malicious bio {i} returned status {res.returncode}, expected exactly 1"
        )


def test_sync_users_script_fixed():
    path = "/home/user/sync_users.sh"
    assert os.path.isfile(path), f"Missing script file: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "/home/user/sync.log" in content, f"Script {path} does not use the absolute path '/home/user/sync.log'."
    assert "PATH=" in content and "/usr/bin" in content, f"Script {path} does not set PATH to include /usr/bin."

    # Ensure PATH is an actual top-level assignment before jq, not merely text
    # placed in a comment while leaving the original broken script unchanged.
    lines = content.splitlines()
    jq_line = next((i for i, line in enumerate(lines) if re.search(r"(^|\s)jq(?:\s|$)", line) and not line.lstrip().startswith("#")), None)
    assert jq_line is not None, f"Script {path} no longer invokes jq"
    path_lines = [
        i for i, line in enumerate(lines)
        if re.match(r"^\s*(?:export\s+)?PATH\s*=", line) and "/usr/bin" in line
    ]
    assert path_lines and path_lines[0] < jq_line, "PATH must be assigned to include /usr/bin before jq is invoked"

    # Execute from an unrelated working directory with an unusable inherited
    # PATH. A correct script must find jq and write only the absolute log path.
    target_log = "/home/user/sync.log"
    try:
        os.remove(target_log)
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory() as workdir:
        env = os.environ.copy()
        env["HOME"] = workdir
        env["PATH"] = os.path.join(workdir, "inherited-path-without-tools")
        result = subprocess.run(
            ["/bin/bash", path],
            cwd=workdir,
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, f"sync_users.sh failed: {result.stderr}"
        assert "command not found" not in result.stderr.lower(), f"jq was not found via the configured PATH: {result.stderr}"
        assert not os.path.exists(os.path.join(workdir, "sync.log")), "sync_users.sh still writes a relative sync.log"

    assert os.path.isfile(target_log), "sync_users.sh did not create /home/user/sync.log"
    with open(target_log, "r") as f:
        assert f.read().strip() == "Synced", "sync_users.sh wrote incorrect log content"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
