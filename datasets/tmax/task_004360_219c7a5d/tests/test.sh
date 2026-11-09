#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import ssl
import subprocess
import tempfile
import time
import pytest

SIGNATURES = ("<script>", "UNION SELECT", "DROP TABLE", "/etc/passwd")


@pytest.fixture(scope="session", autouse=True)
def run_deploy_script():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"{deploy_script} is missing"
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable"

    proc = subprocess.Popen(
        ["bash", deploy_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    time.sleep(3)

    yield

    proc.terminate()
    subprocess.run(["pkill", "-f", "smtpd"], stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "8443"], stderr=subprocess.DEVNULL)
    subprocess.run(["umount", "/home/user/live_logs"], stderr=subprocess.DEVNULL)


def test_bindfs_mount():
    with open("/proc/mounts", "r") as f:
        mounts = f.read()

    assert "/home/user/live_logs" in mounts, "/home/user/live_logs is not mounted"

    try:
        test_file = "/home/user/live_logs/test_ro_write"
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)
        pytest.fail("/home/user/live_logs is not mounted read-only")
    except OSError:
        pass


def test_smtp_server_running():
    try:
        with socket.create_connection(("localhost", 1025), timeout=2):
            pass
    except Exception as e:
        pytest.fail(f"Could not connect to SMTP server on port 1025: {e}")


def test_https_dashboard_running():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    try:
        with socket.create_connection(("localhost", 8443), timeout=2) as sock:
            with context.wrap_socket(sock, server_hostname="localhost") as ssock:
                ssock.sendall(
                    b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
                )
                chunks = []
                while True:
                    chunk = ssock.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
    except Exception as e:
        pytest.fail(f"Could not connect to HTTPS dashboard on port 8443 with TLS: {e}")

    response = b"".join(chunks)
    headers, separator, body = response.partition(b"\r\n\r\n")
    assert separator, "HTTPS dashboard returned an invalid HTTP response"
    status_line = headers.split(b"\r\n", 1)[0]
    assert b" 200 " in status_line, f"HTTPS dashboard returned {status_line!r}"
    assert b"Alerts Dashboard" in body, "Dashboard does not contain 'Alerts Dashboard'"


def expected_output(lines):
    return [
        ("[ALERT] " if any(signature in line for signature in SIGNATURES) else "[OK] ")
        + line
        for line in lines
    ]


def run_and_check_detector(detector_bin, path, input_lines):
    proc = subprocess.run([detector_bin, path], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, (
        f"Detector exited with status {proc.returncode} for {path}:\n{proc.stderr}"
    )

    actual = proc.stdout.splitlines()
    expected = expected_output(input_lines)
    assert len(actual) == len(input_lines), (
        f"Detector emitted {len(actual)} lines for {len(input_lines)} input lines in {path}"
    )
    assert actual == expected, (
        f"Detector output did not preserve and correctly classify every line in {path}. "
        f"Expected {expected!r}, got {actual!r}"
    )
    return actual


def test_detector_adversarial_corpus():
    detector_bin = "/home/user/bin/detector"
    assert os.path.isfile(detector_bin), f"Detector binary not found at {detector_bin}"
    assert os.access(detector_bin, os.X_OK), f"Detector binary is not executable"

    evil_dir = "/home/user/corpora/evil"
    clean_dir = "/home/user/corpora/clean"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, "Evil corpus is empty"
    assert clean_files, "Clean corpus is empty"

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        path = os.path.join(evil_dir, f)
        with open(path, "r") as corpus_file:
            input_lines = corpus_file.read().splitlines()
        assert input_lines, f"Evil corpus file {f} is empty"
        lines = run_and_check_detector(detector_bin, path, input_lines)
        for line in lines:
            if not line.startswith("[ALERT]"):
                evil_bypassed.append(f)
                break

    for f in clean_files:
        path = os.path.join(clean_dir, f)
        with open(path, "r") as corpus_file:
            input_lines = corpus_file.read().splitlines()
        assert input_lines, f"Clean corpus file {f} is empty"
        lines = run_and_check_detector(detector_bin, path, input_lines)
        for line in lines:
            if not line.startswith("[OK]"):
                clean_modified.append(f)
                break

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(clean_modified)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_detector_generated_mixed_input():
    detector_bin = "/home/user/bin/detector"
    nonce = secrets.token_hex(12)
    input_lines = [
        f"{nonce} normal proxy request",
        f"{nonce} payload=<script>alert(1)</script>",
        f"query {nonce} UNION SELECT password FROM users",
        f"admin request DROP TABLE sessions {nonce}",
        f"attempted read /etc/passwd marker={nonce}",
        f"another harmless line {nonce}",
    ]

    path = None
    try:
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".log") as test_log:
            path = test_log.name
            for line in input_lines:
                test_log.write(line + "\n")
        run_and_check_detector(detector_bin, path, input_lines)
    finally:
        if path and os.path.exists(path):
            os.unlink(path)


def test_alert_mailer_fixed():
    mailer_dir = "/app/alert-mailer-1.0.0"

    build_proc = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=mailer_dir,
        capture_output=True,
        text=True,
    )
    assert build_proc.returncode == 0, f"Failed to build alert-mailer:\n{build_proc.stderr}"

    mailer_bin = os.path.join(mailer_dir, "target/release/alert-mailer")
    assert os.path.isfile(mailer_bin), "alert-mailer binary not found after build"

    test_proc = subprocess.run(
        [mailer_bin, "--test"], cwd=mailer_dir, capture_output=True, text=True
    )
    assert test_proc.returncode == 0, (
        "alert-mailer failed to run or connect to port 1025:\n"
        f"{test_proc.stderr}\n{test_proc.stdout}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
