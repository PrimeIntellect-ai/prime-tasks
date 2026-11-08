#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import select
import socket
import subprocess
import tempfile
import threading


def test_env_script():
    env_path = "/home/user/monitor_env.sh"
    assert os.path.isfile(env_path), f"Environment script is missing at {env_path}"

    with open(env_path, 'r') as f:
        content = f.read()

    assert re.search(r'export\s+MONITOR_PORT=9090', content), "MONITOR_PORT=9090 is not exported correctly"
    assert re.search(r'export\s+SMTP_PORT=2525', content), "SMTP_PORT=2525 is not exported correctly"
    assert re.search(r'export\s+ALERT_EMAIL=oncall@staged-deploy\.local', content), "ALERT_EMAIL is not exported correctly"


def test_cpp_source():
    cpp_path = "/home/user/monitor.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file is missing at {cpp_path}"


def test_executable():
    exe_path = "/home/user/monitor"
    assert os.path.isfile(exe_path), f"Executable is missing at {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File at {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The monitor must be a compiled executable"


def test_email_log():
    log_path = "/home/user/email_alerts.log"
    assert os.path.isfile(log_path), f"Email alerts log is missing at {log_path}. Did the monitor run successfully?"

    with open(log_path, 'r') as f:
        content = f.read()

    assert "Subject: Alert: Port Down" in content, "The email subject is missing or incorrect in the log"
    assert "Port 9090 is unresponsive." in content, "The email body is missing or incorrect in the log"


def make_listener():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(5)
    return sock


def run_inactive_case(executable):
    # A bound but non-listening socket reserves a port while ensuring that a TCP
    # connection to it is refused.
    inactive = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    inactive.bind(("127.0.0.1", 0))
    monitor_port = inactive.getsockname()[1]

    smtp = make_listener()
    smtp_port = smtp.getsockname()[1]
    recipient = f"audit-{secrets.token_hex(10)}@staged-deploy.local"
    expected = (
        f"HELO localhost\r\n"
        f"MAIL FROM:<monitor@localhost>\r\n"
        f"RCPT TO:<{recipient}>\r\n"
        f"DATA\r\n"
        f"Subject: Alert: Port Down\r\n"
        f"\r\n"
        f"Port {monitor_port} is unresponsive.\r\n"
        f".\r\n"
        f"QUIT\r\n"
    ).encode()

    result = {"wire": b"", "error": None}

    def smtp_server():
        conn = None
        try:
            smtp.settimeout(8)
            conn, _ = smtp.accept()
            conn.settimeout(5)
            conn.sendall(b"220 Mock SMTP Server Ready\r\n")
            raw = bytearray()
            pending = bytearray()
            in_data = False
            done = False
            while not done:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                raw.extend(chunk)
                pending.extend(chunk)
                while b"\r\n" in pending:
                    line, remainder = pending.split(b"\r\n", 1)
                    pending[:] = remainder
                    upper = line.upper()
                    if in_data:
                        if line == b".":
                            in_data = False
                            conn.sendall(b"250 OK: queued as 12345\r\n")
                    elif upper.startswith(b"HELO"):
                        conn.sendall(b"250 Hello\r\n")
                    elif upper.startswith(b"MAIL FROM:"):
                        conn.sendall(b"250 OK\r\n")
                    elif upper.startswith(b"RCPT TO:"):
                        conn.sendall(b"250 OK\r\n")
                    elif upper == b"DATA":
                        in_data = True
                        conn.sendall(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                    elif upper == b"QUIT":
                        conn.sendall(b"221 Bye\r\n")
                        done = True
                        break
            result["wire"] = bytes(raw)
        except Exception as exc:
            result["error"] = repr(exc)
        finally:
            if conn is not None:
                conn.close()
            smtp.close()

    thread = threading.Thread(target=smtp_server, daemon=True)
    thread.start()
    env = os.environ.copy()
    env.update({
        "MONITOR_PORT": str(monitor_port),
        "SMTP_PORT": str(smtp_port),
        "ALERT_EMAIL": recipient,
    })
    try:
        proc = subprocess.run([executable], env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=10)
    finally:
        inactive.close()
    thread.join(9)

    assert proc.returncode == 0, (
        f"{executable} failed when the monitored port was inactive: "
        f"{proc.stderr.decode(errors='replace')}"
    )
    assert not thread.is_alive(), "The monitor did not complete the SMTP transaction"
    assert result["error"] is None, f"SMTP test server error: {result['error']}"
    assert result["wire"] == expected, (
        "The monitor did not send the required SMTP command sequence using the "
        f"runtime environment values. Expected {expected!r}, got {result['wire']!r}"
    )


def run_active_case(executable):
    monitored = make_listener()
    smtp = make_listener()
    monitor_port = monitored.getsockname()[1]
    smtp_port = smtp.getsockname()[1]
    accepted = threading.Event()

    def service_server():
        try:
            monitored.settimeout(6)
            conn, _ = monitored.accept()
            accepted.set()
            conn.close()
        finally:
            monitored.close()

    thread = threading.Thread(target=service_server, daemon=True)
    thread.start()
    env = os.environ.copy()
    env.update({
        "MONITOR_PORT": str(monitor_port),
        "SMTP_PORT": str(smtp_port),
        "ALERT_EMAIL": f"active-{secrets.token_hex(10)}@staged-deploy.local",
    })
    proc = subprocess.run([executable], env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=10)
    thread.join(7)

    assert proc.returncode == 0, (
        f"{executable} failed while checking an active port: "
        f"{proc.stderr.decode(errors='replace')}"
    )
    assert accepted.is_set(), "The monitor did not connect to MONITOR_PORT"
    readable, _, _ = select.select([smtp], [], [], 0.5)
    smtp.close()
    assert not readable, "The monitor sent an alert even though MONITOR_PORT was active"


def test_monitor_behavior_and_source_build():
    source = "/home/user/monitor.cpp"
    submitted = "/home/user/monitor"

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "rebuilt-monitor")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert compile_result.returncode == 0, (
            "monitor.cpp does not compile: " +
            compile_result.stderr.decode(errors="replace")
        )

        # Exercise the submitted artifact itself.
        run_inactive_case(submitted)
        run_active_case(submitted)

        # Also exercise a fresh build from the submitted source while the original
        # executable is unavailable, so the source must implement the behavior.
        hidden = os.path.join(directory, "submitted-monitor")
        os.rename(submitted, hidden)
        try:
            run_inactive_case(rebuilt)
            run_active_case(rebuilt)
        finally:
            os.rename(hidden, submitted)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
