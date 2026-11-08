#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import socket
import subprocess
import tempfile
import threading
import time


def _find_logrotate_block(content, target):
    without_comments = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    pattern = re.compile(r"(?m)^[ \t]*(?P<header>[^\n{}]+?)[ \t]*(?:\n[ \t]*)?\{")
    for match in pattern.finditer(without_comments):
        end = without_comments.find("}", match.end())
        if end == -1:
            continue
        try:
            paths = shlex.split(match.group("header"))
        except ValueError:
            continue
        if target in paths:
            return without_comments, match.end(), without_comments[match.end():end]
    raise AssertionError(f"No logrotate block targets {target}.")


def test_logrotate_conf():
    path = "/home/user/logrotate.conf"
    target = "/home/user/logs/smtp_monitor.log"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "size 10" in content or "size 10b" in content or "size=10" in content.replace(" ", ""), "Missing 'size 10' directive in logrotate.conf"
    assert "rotate 3" in content, "Missing 'rotate 3' directive in logrotate.conf"
    assert "compress" in content, "Missing 'compress' directive in logrotate.conf"
    assert "missingok" in content, "Missing 'missingok' directive in logrotate.conf"
    assert "nomail" in content, "Missing 'nomail' directive in logrotate.conf"

    cleaned, body_start, body = _find_logrotate_block(content, target)
    directives = []
    for line in body.splitlines():
        line = line.strip()
        if line:
            directives.append(line.split())

    sizes = [parts[1].lower() for parts in directives if parts[0].lower() == "size" and len(parts) == 2]
    rotations = [parts[1] for parts in directives if parts[0].lower() == "rotate" and len(parts) == 2]
    assert sizes and sizes[-1] in ("10", "10b"), "The target block must effectively use size 10 bytes."
    assert rotations and rotations[-1] == "3", "The target block must effectively keep exactly 3 backups."

    switches = [parts[0].lower() for parts in directives if len(parts) == 1]
    compression = [x for x in switches if x in ("compress", "nocompress")]
    missing = [x for x in switches if x in ("missingok", "nomissingok")]
    mailing = [x for x in switches if x in ("mail", "nomail")]
    assert compression and compression[-1] == "compress", "Compression is not enabled for the target log."
    assert missing and missing[-1] == "missingok", "missingok is not enabled for the target log."
    assert mailing and mailing[-1] == "nomail", "nomail is not enabled for the target log."

    # Ask logrotate itself to parse the configuration. Injecting su only avoids the
    # setup's intentionally world-writable /home/user tree from causing a security skip.
    parse_content = cleaned[:body_start] + "\n    su user user\n" + cleaned[body_start:]
    with tempfile.TemporaryDirectory() as td:
        parse_conf = os.path.join(td, "logrotate.conf")
        state_file = os.path.join(td, "state")
        with open(parse_conf, "w") as f:
            f.write(parse_content)
        result = subprocess.run(
            ["logrotate", "--debug", "--state", state_file, parse_conf],
            capture_output=True,
            text=True,
            env={**os.environ, "LC_ALL": "C"},
        )
        assert result.returncode == 0, f"logrotate rejected the configuration:\n{result.stdout}\n{result.stderr}"


def test_supervisor_script():
    path = "/home/user/supervisor.sh"
    binary_path = "/home/user/smtp_monitor/target/debug/smtp_monitor"
    assert os.path.isfile(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "smtp_monitor" in content, "Supervisor script does not seem to call the smtp_monitor binary."
    assert "sleep 1" in content, "Supervisor script does not seem to sleep for 1 second on failure."

    backup_path = binary_path + ".verifier-backup"
    test_dir = tempfile.mkdtemp(prefix="supervisor-test-")
    count_path = os.path.join(test_dir, "count")
    mode_path = os.path.join(test_dir, "mode")
    stub = f'''#!/bin/bash
echo run >> {shlex.quote(count_path)}
if [ "$(cat {shlex.quote(mode_path)})" = "fail-once" ] && [ "$(wc -l < {shlex.quote(count_path)})" -eq 1 ]; then
    exit 7
fi
exit 0
'''

    os.replace(binary_path, backup_path)
    try:
        with open(binary_path, "w") as f:
            f.write(stub)
        os.chmod(binary_path, 0o755)

        with open(mode_path, "w") as f:
            f.write("fail-once")
        start = time.monotonic()
        result = subprocess.run([path], capture_output=True, text=True, timeout=5)
        elapsed = time.monotonic() - start
        assert result.returncode == 0, "Supervisor must exit 0 after a restarted child succeeds."
        with open(count_path) as f:
            runs = f.read().splitlines()
        assert len(runs) == 2, "Supervisor must restart the binary after a non-zero exit, then stop after success."
        assert elapsed >= 0.85, "Supervisor did not wait approximately 1 second before restarting."

        os.remove(count_path)
        with open(mode_path, "w") as f:
            f.write("succeed")
        start = time.monotonic()
        result = subprocess.run([path], capture_output=True, text=True, timeout=3)
        elapsed = time.monotonic() - start
        assert result.returncode == 0, "Supervisor must propagate graceful success as exit code 0."
        with open(count_path) as f:
            runs = f.read().splitlines()
        assert len(runs) == 1, "Supervisor must not restart the binary after exit code 0."
        assert elapsed < 0.8, "Supervisor should terminate promptly when the binary exits successfully."
    finally:
        if os.path.exists(binary_path):
            os.remove(binary_path)
        os.replace(backup_path, binary_path)
        for name in (count_path, mode_path):
            if os.path.exists(name):
                os.remove(name)
        os.rmdir(test_dir)


def test_rust_project_builds():
    project_dir = "/home/user/smtp_monitor"
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isfile(os.path.join(project_dir, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(project_dir, "src", "main.rs")), "src/main.rs is missing."

    result = subprocess.run(["cargo", "build"], cwd=project_dir, capture_output=True)
    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr.decode()}"


def start_dummy_server(port, stop_event):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", port))
        s.settimeout(0.5)
        s.listen(1)
        while not stop_event.is_set():
            try:
                conn, _ = s.accept()
                conn.close()
                break
            except socket.timeout:
                continue


def test_rust_logic_and_side_effects():
    binary_path = "/home/user/smtp_monitor/target/debug/smtp_monitor"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}."

    aliases_path = "/home/user/mail_aliases.txt"
    log_path = "/home/user/logs/smtp_monitor.log"

    with open(aliases_path, "w") as f:
        f.write("sysadmins: root, admin\nnet-admins: bob, charlie\n")
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run([binary_path], capture_output=True)
    assert result.returncode == 1, "Binary should exit with status 1 when all connections fail."

    assert os.path.isfile(log_path), "Log file was not created."
    with open(log_path, "r") as f:
        logs = f.read().splitlines()
    assert len(logs) == 3, "Should have made exactly 3 attempts."
    assert all(line == "CONNECT_FAIL" for line in logs), "Logs should contain CONNECT_FAIL for failed attempts."

    with open(aliases_path, "r") as f:
        aliases_content = f.read()
    assert "net-admins: bob, charlie, alice" in aliases_content or "alice" in aliases_content.split("net-admins:")[1].split("\n")[0], "User 'alice' was not properly appended to net-admins."

    os.remove(log_path)
    stop_event = threading.Event()
    server_thread = threading.Thread(target=start_dummy_server, args=(2525, stop_event))
    server_thread.start()

    try:
        time.sleep(0.2)
        result = subprocess.run([binary_path], capture_output=True)
        assert result.returncode == 0, "Binary should exit with status 0 when at least one connection succeeds."

        with open(log_path, "r") as f:
            logs = f.read().splitlines()
        assert "CONNECT_OK" in logs, "Logs should contain CONNECT_OK for successful attempts."
    finally:
        stop_event.set()
        server_thread.join()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
