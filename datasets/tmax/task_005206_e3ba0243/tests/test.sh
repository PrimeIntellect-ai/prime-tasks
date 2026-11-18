#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import secrets
import signal
import socket
import ssl
import subprocess
import sys
import time
from datetime import datetime

BASE_DIR = "/home/user/deploy_system"
PUBLIC_DIR = os.path.join(BASE_DIR, "public")
PAYLOAD_FILE = os.path.join(PUBLIC_DIR, "payload.json")
MANAGER_SCRIPT = os.path.join(BASE_DIR, "manager.py")
CERT_FILE = os.path.join(BASE_DIR, "cert.pem")
KEY_FILE = os.path.join(BASE_DIR, "key.pem")
TEST_RESULT_FILE = os.path.join(BASE_DIR, "test_result.txt")
APP_PID_FILE = os.path.join(BASE_DIR, "app.pid")
APP_LOG_FILE = os.path.join(BASE_DIR, "app.log")
EXPECTED_PAYLOAD = '{"status": "securely deployed"}'


def process_alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except (OSError, FileNotFoundError, ProcessLookupError):
        return False


def port_is_free():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", 9443)) != 0


def pid_listens_on_9443(pid):
    inodes = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                inodes.add(target[8:-1])
    except OSError:
        return False

    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        port = int(fields[1].split(":")[1], 16)
                        state = fields[3]
                        inode = fields[9]
                        if port == 9443 and state == "0A" and inode in inodes:
                            return True
        except OSError:
            pass
    return False


def wait_until(predicate, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


def run_checked(args, timeout=10):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout, check=True)


def test_payload_file():
    """Verify the payload.json file exists and has the correct content."""
    assert os.path.exists(PAYLOAD_FILE), f"File {PAYLOAD_FILE} does not exist."
    with open(PAYLOAD_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_PAYLOAD, f"Incorrect content in {PAYLOAD_FILE}."


def test_manager_script_exists():
    """Verify the manager.py script exists."""
    assert os.path.exists(MANAGER_SCRIPT), f"File {MANAGER_SCRIPT} does not exist."
    assert os.path.isfile(MANAGER_SCRIPT), f"{MANAGER_SCRIPT} is not a file."
    run_checked([sys.executable, "-m", "py_compile", MANAGER_SCRIPT])


def test_certificates_exist():
    """Verify the TLS certificate and key exist."""
    assert os.path.exists(CERT_FILE), f"Certificate file {CERT_FILE} does not exist."
    assert os.path.exists(KEY_FILE), f"Key file {KEY_FILE} does not exist."


def test_test_result_file():
    """Verify the curl test result exists and has the correct output."""
    assert os.path.exists(TEST_RESULT_FILE), f"File {TEST_RESULT_FILE} does not exist."
    with open(TEST_RESULT_FILE, "r") as f:
        content = f.read().strip()
    assert EXPECTED_PAYLOAD in content, f"Incorrect content in {TEST_RESULT_FILE}."
    assert content == EXPECTED_PAYLOAD, f"{TEST_RESULT_FILE} is not the exact fetched payload."


def test_pid_file_cleaned_up():
    """Verify the PID file was deleted after stopping the server."""
    assert not os.path.exists(APP_PID_FILE), f"PID file {APP_PID_FILE} still exists, indicating the server was not stopped cleanly."


def test_log_file_exists():
    """Verify the application log file exists."""
    assert os.path.exists(APP_LOG_FILE), f"Log file {APP_LOG_FILE} does not exist."


def test_port_9443_is_free():
    """Verify that port 9443 is no longer in use."""
    assert port_is_free(), "Port 9443 is still in use. The server process was not properly terminated."


def test_manager_full_lifecycle_and_tls(tmp_path):
    """Exercise certificate creation, HTTPS serving, PID ownership, logging, and stop."""
    tracker_dir = tmp_path / "tracker"
    tracker_dir.mkdir()
    tracker_log = tracker_dir / "subprocess.log"
    sitecustomize = tracker_dir / "sitecustomize.py"
    sitecustomize.write_text(
        "import os, subprocess\n"
        "_original_popen = subprocess.Popen\n"
        "def _tracked_popen(*args, **kwargs):\n"
        "    path = os.environ.get('MANAGER_SUBPROCESS_LOG')\n"
        "    if path:\n"
        "        try:\n"
        "            with open(path, 'a') as f:\n"
        "                f.write(str(os.getpid()) + '\\t' + repr(args) + '\\t' + repr(kwargs) + '\\n')\n"
        "        except Exception:\n"
        "            pass\n"
        "    return _original_popen(*args, **kwargs)\n"
        "subprocess.Popen = _tracked_popen\n"
    )

    dynamic_payload = json.dumps({
        "status": "verification-" + secrets.token_hex(16),
        "nonce": secrets.token_hex(24),
    }, separators=(",", ":"))
    pid = None
    stopped = False
    env = os.environ.copy()
    env["PYTHONPATH"] = str(tracker_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["MANAGER_SUBPROCESS_LOG"] = str(tracker_log)

    try:
        assert port_is_free(), "Port 9443 must be free before starting the submitted manager."
        for path in (CERT_FILE, KEY_FILE, APP_PID_FILE):
            if os.path.lexists(path):
                os.unlink(path)
        with open(PAYLOAD_FILE, "w") as f:
            f.write(dynamic_payload)

        started = subprocess.run(
            [sys.executable, MANAGER_SCRIPT, "start"],
            cwd=BASE_DIR, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15,
        )
        assert started.returncode == 0, f"manager.py start failed: {started.stdout}\n{started.stderr}"
        assert os.path.isfile(APP_PID_FILE), "start did not create app.pid."
        with open(APP_PID_FILE, "r") as f:
            raw_pid = f.read().strip()
        assert raw_pid.isdigit() and int(raw_pid) > 1, "app.pid does not contain a valid PID."
        pid = int(raw_pid)
        assert process_alive(pid), "The PID recorded by start is not a running process."

        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\0", b" ").lower()
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower()
        assert exe.startswith("python") or b"python" in cmdline, "The recorded server PID is not a Python process."
        assert wait_until(lambda: pid_listens_on_9443(pid)), "The recorded PID never listened on port 9443."

        assert os.path.isfile(APP_LOG_FILE), "start did not create app.log."
        for fd in ("1", "2"):
            fd_path = f"/proc/{pid}/fd/{fd}"
            assert os.path.exists(fd_path), f"Server file descriptor {fd} is closed."
            assert os.path.samefile(fd_path, APP_LOG_FILE), f"Server fd {fd} is not redirected to app.log."

        assert os.path.isfile(CERT_FILE) and os.path.getsize(CERT_FILE) > 0, "start did not generate cert.pem."
        assert os.path.isfile(KEY_FILE) and os.path.getsize(KEY_FILE) > 0, "start did not generate key.pem."
        events = tracker_log.read_text() if tracker_log.exists() else ""
        assert "openssl" in events.lower(), "Certificate generation did not invoke openssl through Python subprocess."

        cert_text = run_checked(["openssl", "x509", "-in", CERT_FILE, "-noout", "-subject", "-issuer", "-dates", "-text"]).stdout
        assert "Public-Key: (2048 bit)" in cert_text, "Certificate does not use an RSA-2048 public key."
        subject = next(line for line in cert_text.splitlines() if line.startswith("subject="))
        issuer = next(line for line in cert_text.splitlines() if line.startswith("issuer="))
        assert "CN = localhost" in subject or "CN=localhost" in subject, "Certificate CN is not localhost."
        assert subject[len("subject="):].strip() == issuer[len("issuer="):].strip(), "Certificate is not self-signed."
        dates = {}
        for line in cert_text.splitlines():
            if line.startswith("notBefore=") or line.startswith("notAfter="):
                key, value = line.split("=", 1)
                dates[key] = datetime.strptime(" ".join(value.split()), "%b %d %H:%M:%S %Y %Z")
        validity = (dates["notAfter"] - dates["notBefore"]).total_seconds()
        assert abs(validity - 365 * 86400) <= 60, "Certificate validity is not 365 days."
        run_checked(["openssl", "verify", "-CAfile", CERT_FILE, CERT_FILE])
        cert_pub = run_checked(["openssl", "x509", "-in", CERT_FILE, "-pubkey", "-noout"]).stdout
        key_pub = run_checked(["openssl", "pkey", "-in", KEY_FILE, "-pubout"]).stdout
        assert cert_pub == key_pub, "cert.pem and key.pem do not match or the key requires a passphrase."

        context = ssl._create_unverified_context()
        response_body = None
        deadline = time.time() + 8
        last_error = None
        while time.time() < deadline:
            conn = None
            try:
                conn = http.client.HTTPSConnection("localhost", 9443, context=context, timeout=2)
                conn.request("GET", "/payload.json")
                response = conn.getresponse()
                body = response.read().decode("utf-8")
                assert response.status == 200, f"HTTPS server returned status {response.status}."
                response_body = body
                break
            except (OSError, ssl.SSLError) as exc:
                last_error = exc
                time.sleep(0.1)
            finally:
                if conn is not None:
                    conn.close()
        assert response_body is not None, f"Could not fetch payload over HTTPS: {last_error}"
        assert response_body == dynamic_payload, "HTTPS server did not serve the verifier-generated payload from public/."

        stopped_result = subprocess.run(
            [sys.executable, MANAGER_SCRIPT, "stop"],
            cwd=BASE_DIR, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15,
        )
        assert stopped_result.returncode == 0, f"manager.py stop failed: {stopped_result.stdout}\n{stopped_result.stderr}"
        stopped = True
        assert wait_until(lambda: not process_alive(pid), timeout=8), "stop did not terminate the recorded server PID."
        assert not os.path.exists(APP_PID_FILE), "stop did not delete app.pid."
        assert wait_until(port_is_free, timeout=5), "Port 9443 remained in use after stop."
    finally:
        with open(PAYLOAD_FILE, "w") as f:
            f.write(EXPECTED_PAYLOAD)
        if pid is not None and process_alive(pid):
            try:
                subprocess.run([sys.executable, MANAGER_SCRIPT, "stop"], cwd=BASE_DIR,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            except Exception:
                pass
            if process_alive(pid):
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
            if not wait_until(lambda: not process_alive(pid), timeout=2):
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
