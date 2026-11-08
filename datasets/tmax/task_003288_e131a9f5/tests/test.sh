#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import socket
import subprocess
import threading
from pathlib import Path

SCRIPT = "/home/user/check_uptime.py"
REPORT = "/home/user/uptime_report.txt"


def test_bashrc_contains_export():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    match = re.search(r'export\s+QEMU_MONITOR_SOCKET\s*=\s*[\'\"]?/home/user/qemu-monitor\.sock[\'\"]?', content)
    assert match is not None, f"Could not find 'export QEMU_MONITOR_SOCKET=/home/user/qemu-monitor.sock' in {bashrc_path}."


def test_check_uptime_script_exists_and_valid():
    script_path = SCRIPT
    assert os.path.exists(script_path), f"Python script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."

    with open(script_path, "r") as f:
        content = f.read()

    assert "pexpect" in content, f"The script {script_path} does not seem to use 'pexpect'."
    assert "QEMU_MONITOR_SOCKET" in content, f"The script {script_path} does not read the 'QEMU_MONITOR_SOCKET' environment variable."

    tree = ast.parse(content, filename=script_path)
    pexpect_modules = set()
    spawn_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    pexpect_modules.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_names.add(alias.asname or "spawn")

    uses_spawn = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute)
             and node.func.attr == "spawn"
             and isinstance(node.func.value, ast.Name)
             and node.func.value.id in pexpect_modules)
            or (isinstance(node.func, ast.Name) and node.func.id in spawn_names)
        )
        for node in ast.walk(tree)
    )
    assert uses_spawn, "The script must use pexpect.spawn to create the nc connection."


def test_uptime_report_content():
    report_path = REPORT
    assert os.path.exists(report_path), f"Report file {report_path} does not exist. Did you run your script?"

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected = "STATUS: OK - Uptime: 1337 days, 04:20:00"
    assert content == expected, f"Expected report content '{expected}', but got '{content}'."


def _install_nc_audit_wrapper(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    wrapper = bin_dir / "nc"
    wrapper.write_text(
        '#!/bin/sh\n'
        'printf "%s\\n" "$@" > "$NC_AUDIT_LOG"\n'
        'exec /usr/bin/nc "$@"\n'
    )
    wrapper.chmod(0o755)
    return bin_dir


def test_script_executes_full_monitor_protocol(tmp_path):
    socket_path = str(tmp_path / "monitor.sock")
    audit_log = str(tmp_path / "nc-args.txt")
    bin_dir = _install_nc_audit_wrapper(tmp_path)
    uptime = f"{secrets.randbelow(8000) + 2000} days, {secrets.randbelow(24):02d}:{secrets.randbelow(60):02d}:{secrets.randbelow(60):02d}"
    observed = {}
    ready = threading.Event()
    server_errors = []

    def server():
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            srv.bind(socket_path)
            srv.listen(1)
            srv.settimeout(15)
            ready.set()
            conn, _ = srv.accept()
            with conn:
                conn.settimeout(10)
                stream = conn.makefile("rwb", buffering=0)
                stream.write(b"login: ")
                observed["username"] = stream.readline().decode(errors="replace").strip()
                stream.write(b"Password: ")
                observed["password"] = stream.readline().decode(errors="replace").strip()
                stream.write(b"\n(qemu) ")
                observed["command"] = stream.readline().decode(errors="replace").strip()
                stream.write((f"\nVM uptime: {uptime}\n(qemu) ").encode())
                observed["quit"] = stream.readline().decode(errors="replace").strip()
        except Exception as exc:
            server_errors.append(repr(exc))
            ready.set()
        finally:
            srv.close()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(5), "Mock monitor did not start."
    assert not server_errors, f"Mock monitor failed to start: {server_errors}"

    Path(REPORT).unlink(missing_ok=True)
    env = os.environ.copy()
    env["QEMU_MONITOR_SOCKET"] = socket_path
    env["NC_AUDIT_LOG"] = audit_log
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        ["python3", SCRIPT], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    thread.join(10)

    assert not thread.is_alive(), "The script did not send quit and close the monitor session."
    assert not server_errors, f"Mock monitor error: {server_errors}"
    assert observed.get("username") == "sre_admin", f"Wrong login: {observed}"
    assert observed.get("password") == "monitor123", f"Wrong password: {observed}"
    assert observed.get("command") == "info uptime", f"Wrong monitor command: {observed}"
    assert observed.get("quit") == "quit", f"The script did not exit with quit: {observed}"
    assert os.path.exists(audit_log), "The script did not invoke nc from pexpect."
    assert Path(audit_log).read_text().splitlines() == ["-U", socket_path], "nc must be invoked as nc -U <socket_path>."
    assert os.path.exists(REPORT), f"The executed script did not create {REPORT}. stderr: {result.stderr}"
    assert Path(REPORT).read_text().strip() == f"STATUS: OK - Uptime: {uptime}"


def test_script_writes_error_when_connection_fails(tmp_path):
    missing_socket = str(tmp_path / "does-not-exist.sock")
    Path(REPORT).unlink(missing_ok=True)
    env = os.environ.copy()
    env["QEMU_MONITOR_SOCKET"] = missing_socket
    result = subprocess.run(
        ["python3", SCRIPT], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert os.path.exists(REPORT), f"No error report was written. stderr: {result.stderr}"
    assert Path(REPORT).read_text().strip() == "STATUS: ERROR"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
