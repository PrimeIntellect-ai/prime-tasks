#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import ssl
import subprocess
import tarfile
import tempfile
import time

import pytest


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return result


def kill_listeners(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def unused_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_listener(port, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"No listener appeared on localhost:{port}")


def terminate_process(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def send_and_read(port, payload, require_close=True):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as s:
        s.settimeout(2)
        s.sendall(payload)
        s.shutdown(socket.SHUT_WR)
        chunks = []
        closed = False
        while True:
            try:
                part = s.recv(4096)
            except socket.timeout:
                break
            if not part:
                closed = True
                break
            chunks.append(part)
        if require_close:
            assert closed, "Daemon did not close the client connection"
        return b"".join(chunks)


def exercise_daemon(executable):
    port = unused_port()
    with tempfile.TemporaryDirectory() as alert_dir:
        env = os.environ.copy()
        env["ALERT_PORT"] = str(port)
        env["ALERT_DIR"] = alert_dir
        proc = subprocess.Popen(
            [executable], env=env, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )
        try:
            wait_for_listener(port)
            log_path = os.path.join(alert_dir, "alerts.log")
            if os.path.exists(log_path):
                assert open(log_path, "rb").read() == b""

            for invalid in (b"XTRIGGER\n", b"TRIGGER\nextra", b"TRIGGER", b"trigger\n"):
                try:
                    send_and_read(port, invalid, require_close=False)
                except (ConnectionResetError, BrokenPipeError):
                    pass
                time.sleep(0.05)

            invalid_content = open(log_path, "rb").read() if os.path.exists(log_path) else b""
            assert invalid_content == b"", "A non-exact request incorrectly fired an alert"

            assert send_and_read(port, b"TRIGGER\n") == b"OK\n"
            assert send_and_read(port, b"TRIGGER\n") == b"OK\n"
            assert proc.poll() is None, "Daemon did not remain running for consecutive connections"
            assert open(log_path, "rb").read() == b"ALERT_FIRED\nALERT_FIRED\n"
        finally:
            terminate_process(proc)
            kill_listeners(port)


def test_directories_exist():
    directories = [
        "/home/user/alerts", "/home/user/backups", "/home/user/src",
        "/home/user/bin", "/home/user/certs"
    ]
    for directory in directories:
        assert os.path.isdir(directory), f"Directory {directory} is missing."


def test_bashrc_env_vars():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} is missing."
    with open(bashrc_path) as f:
        content = f.read()
    assert re.search(r"ALERT_DIR\s*=\s*['\"]?/home/user/alerts['\"]?", content), "ALERT_DIR is not correctly set in .bashrc"
    assert re.search(r"ALERT_PORT\s*=\s*['\"]?8080['\"]?", content), "ALERT_PORT is not correctly set in .bashrc"

    loaded = subprocess.run(
        ["bash", "--noprofile", "-c", "source /home/user/.bashrc; printf '%s\\n%s' \"$ALERT_DIR\" \"$ALERT_PORT\""],
        capture_output=True, text=True, timeout=3, check=True
    ).stdout.splitlines()
    assert loaded == ["/home/user/alerts", "8080"], ".bashrc does not load the required values"


def test_daemon_files_exist():
    src_path = "/home/user/src/alert_daemon.c"
    bin_path = "/home/user/bin/alert_daemon"
    assert os.path.isfile(src_path), f"C source file {src_path} is missing."
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "alert_daemon is not a compiled executable"


def test_daemon_behavior():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("127.0.0.1", 8080))
        s.sendall(b"TRIGGER\n")
        data = s.recv(1024)
        s.close()
    except Exception as exc:
        assert False, f"Failed to connect to daemon on port 8080 or send data: {exc}"
    assert b"OK" in data, f"Daemon did not reply with OK, got: {data}"


def test_alerts_log_content():
    log_path = "/home/user/alerts/alerts.log"
    assert os.path.isfile(log_path), f"Alert log {log_path} is missing."
    with open(log_path) as f:
        content = f.read()
    assert "ALERT_FIRED" in content, "alerts.log does not contain 'ALERT_FIRED'."


def test_daemon_artifacts_functionally():
    exercise_daemon("/home/user/bin/alert_daemon")
    rebuilt = "/tmp/rebuilt_alert_daemon"
    subprocess.run(
        ["gcc", "/home/user/src/alert_daemon.c", "-o", rebuilt],
        check=True, capture_output=True, text=True, timeout=15
    )
    exercise_daemon(rebuilt)


def test_tls_certs():
    crt_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"
    assert os.path.isfile(crt_path), f"Certificate {crt_path} is missing."
    assert os.path.isfile(key_path), f"Private key {key_path} is missing."
    with open(crt_path) as f:
        assert "BEGIN CERTIFICATE" in f.read(), f"{crt_path} does not look like a valid PEM certificate."
    with open(key_path) as f:
        assert "PRIVATE KEY" in f.read(), f"{key_path} does not look like a valid PEM private key."

    subprocess.run(["openssl", "x509", "-in", crt_path, "-noout"], check=True, timeout=5, capture_output=True)
    key_info = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-noout", "-text"],
        check=True, timeout=5, capture_output=True, text=True
    ).stdout
    assert re.search(r"(?:Private-Key|RSA Private-Key): \(2048 bit", key_info), "Private key is not RSA 2048-bit"
    cert_pub = subprocess.run(["openssl", "x509", "-in", crt_path, "-pubkey", "-noout"], check=True, capture_output=True, timeout=5).stdout
    key_pub = subprocess.run(["openssl", "pkey", "-in", key_path, "-pubout"], check=True, capture_output=True, timeout=5).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_scripts_exist():
    serve_script = "/home/user/serve_logs.sh"
    backup_script = "/home/user/backup.sh"
    assert os.path.isfile(serve_script), f"Script {serve_script} is missing."
    assert os.access(serve_script, os.X_OK), f"Script {serve_script} is not executable."
    assert os.path.isfile(backup_script), f"Script {backup_script} is missing."
    assert os.access(backup_script, os.X_OK), f"Script {backup_script} is not executable."


def test_existing_backup_archive():
    backup_path = "/home/user/backups/alerts_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive {backup_path} is missing."
    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            assert any("alerts.log" in name for name in names), "alerts.log is not present in the backup archive."
            members = [m for m in tar.getmembers() if os.path.basename(m.name) == "alerts.log" and m.isfile()]
            assert members, "The backup does not contain a regular alerts.log file"
            assert any(b"ALERT_FIRED\n" in tar.extractfile(m).read() for m in members), "Backed-up alerts.log lacks the alert content"
    except tarfile.TarError as exc:
        assert False, f"Failed to read tar.gz archive {backup_path}: {exc}"


def test_backup_script_execution_and_content():
    marker = b"dynamic-backup-content-7f03c1\n"
    with tempfile.TemporaryDirectory() as alert_dir:
        with open(os.path.join(alert_dir, "alerts.log"), "wb") as f:
            f.write(marker)
        env = os.environ.copy()
        env["ALERT_DIR"] = alert_dir
        subprocess.run(["/home/user/backup.sh"], env=env, check=True, timeout=10, capture_output=True)

    backup_path = "/home/user/backups/alerts_backup.tar.gz"
    assert os.path.isfile(backup_path)
    with tarfile.open(backup_path, "r:gz") as tar:
        members = [m for m in tar.getmembers() if os.path.basename(m.name) == "alerts.log" and m.isfile()]
        assert len(members) == 1, "Backup must contain the alerts.log regular file"
        assert tar.extractfile(members[0]).read() == marker, "Backup does not contain the current $ALERT_DIR/alerts.log content"


def test_serve_logs_script_execution():
    marker = b"tls-log-marker-91b70e\n"
    kill_listeners(8443)
    with tempfile.TemporaryDirectory() as alert_dir:
        with open(os.path.join(alert_dir, "alerts.log"), "wb") as f:
            f.write(marker)
        env = os.environ.copy()
        env["ALERT_DIR"] = alert_dir
        subprocess.run(
            ["/home/user/serve_logs.sh"], env=env, check=True, timeout=3,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            wait_for_listener(8443, timeout=5)
            pids = listener_pids(8443)
            assert pids, "serve_logs.sh did not leave a background server running"
            is_s_server = False
            for pid in pids:
                try:
                    exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
                    cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ")
                    if exe.startswith("openssl") and b"s_server" in cmd:
                        is_s_server = True
                except OSError:
                    pass
            assert is_s_server, "Port 8443 is not being served by openssl s_server"

            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            with socket.create_connection(("127.0.0.1", 8443), timeout=3) as raw:
                with context.wrap_socket(raw, server_hostname="localhost") as tls:
                    tls.settimeout(3)
                    expected_der = ssl.PEM_cert_to_DER_cert(open("/home/user/certs/server.crt").read())
                    assert tls.getpeercert(binary_form=True) == expected_der, "TLS server did not use server.crt"
                    tls.sendall(b"GET /alerts.log HTTP/1.0\r\nHost: localhost\r\n\r\n")
                    received = bytearray()
                    closed = False
                    while True:
                        try:
                            chunk = tls.recv(4096)
                        except ssl.SSLZeroReturnError:
                            closed = True
                            break
                        except socket.timeout:
                            break
                        if not chunk:
                            closed = True
                            break
                        received.extend(chunk)
                    assert marker in bytes(received), "TLS server did not serve $ALERT_DIR/alerts.log"
                    assert closed, "TLS server did not close after serving the file"
        finally:
            kill_listeners(8443)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
