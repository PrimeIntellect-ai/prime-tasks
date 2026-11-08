#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import os
import random
import re
import shutil
import socket
import subprocess
import tarfile
import threading
import time

MIGRATION_DIR = "/home/user/migration"
PORTS = [8081, 8082, 8083]


def test_directory_structure():
    app_data_dir = os.path.join(MIGRATION_DIR, "app_data")
    active_apps_dir = os.path.join(MIGRATION_DIR, "active_apps")

    for i in range(1, 4):
        server_dir = os.path.join(app_data_dir, f"server{i}")
        assert os.path.isdir(server_dir), f"Directory {server_dir} does not exist."

        symlink_path = os.path.join(active_apps_dir, f"app{i}")
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

        target = os.readlink(symlink_path)
        if not os.path.isabs(target):
            target = os.path.normpath(os.path.join(active_apps_dir, target))
        assert target == server_dir, f"Symlink {symlink_path} does not point to {server_dir}."


def extract_blocks(text, header_pattern):
    blocks = []
    for match in re.finditer(header_pattern, text, re.MULTILINE):
        opening = text.find("{", match.start(), match.end())
        if opening < 0:
            continue
        depth = 0
        for pos in range(opening, len(text)):
            if text[pos] == "{":
                depth += 1
            elif text[pos] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[opening + 1:pos])
                    break
    return blocks


def test_nginx_configuration():
    nginx_conf = os.path.join(MIGRATION_DIR, "nginx.conf")
    nginx_run = os.path.join(MIGRATION_DIR, "nginx_run")

    assert os.path.isfile(nginx_conf), f"Nginx configuration {nginx_conf} does not exist."
    assert os.path.isdir(nginx_run), f"Nginx run directory {nginx_run} does not exist."

    result = subprocess.run(["nginx", "-t", "-c", nginx_conf], capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx configuration syntax check failed:\n{result.stderr}"

    result = subprocess.run(["nginx", "-T", "-c", nginx_conf], capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx configuration dump failed:\n{result.stderr}"
    config_output = result.stdout

    directives = ["pid", "client_body_temp_path", "proxy_temp_path",
                  "fastcgi_temp_path", "uwsgi_temp_path", "scgi_temp_path",
                  "access_log", "error_log"]
    for directive in directives:
        # Retain the original path-presence assertion and additionally associate
        # the required path with the named directive.
        assert nginx_run in config_output, f"Directive {directive} does not seem to use {nginx_run}."
        pattern = rf"(?m)^\s*{re.escape(directive)}\s+['\"]?{re.escape(nginx_run)}/[^;\s'\"]+"
        assert re.search(pattern, config_output), \
            f"Directive {directive} is not configured with a path inside {nginx_run}/."

    assert "upstream backend_cluster" in config_output, "Upstream block 'backend_cluster' not found."
    upstreams = extract_blocks(config_output, r"\bupstream\s+backend_cluster\s*\{")
    assert upstreams, "Upstream block 'backend_cluster' not found."
    upstream = upstreams[0]
    configured_backends = re.findall(r"(?m)^\s*server\s+([^;\s]+)", upstream)
    expected_backends = {f"127.0.0.1:{port}" for port in PORTS}
    for port in PORTS:
        assert f"127.0.0.1:{port}" in config_output, \
            f"Upstream server 127.0.0.1:{port} not found in config."
    assert set(configured_backends) == expected_backends and len(configured_backends) == 3, \
        f"backend_cluster must contain exactly {sorted(expected_backends)}, got {configured_backends}."
    assert not re.search(r"(?m)^\s*(least_conn|ip_hash|hash|random)\b", upstream), \
        "backend_cluster is not using the required default round-robin balancing."

    assert "listen 127.0.0.1:8080" in config_output or "listen 8080" in config_output, \
        "Nginx is not configured to listen on 127.0.0.1:8080."

    server_blocks = extract_blocks(config_output, r"\bserver\s*\{")
    matching_server = None
    for block in server_blocks:
        if re.search(r"(?m)^\s*listen\s+127\.0\.0\.1:8080(?:\s|;)", block):
            matching_server = block
            break
    assert matching_server is not None, "No server block listens specifically on 127.0.0.1:8080."

    locations = extract_blocks(matching_server, r"\blocation\s+(?:=\s*)?/(?=\s*\{)")
    assert locations, "A location for / was not found in the 127.0.0.1:8080 server block."
    assert any(re.search(r"(?m)^\s*proxy_pass\s+http://backend_cluster/?\s*;", block)
               for block in locations), \
        "The / location does not proxy traffic to backend_cluster."


def constant_number(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.FloorDiv)):
        left = constant_number(node.left)
        right = constant_number(node.right)
        if left is None or right is None:
            return None
        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        if right != 0:
            return left // right
    return None


def test_monitor_logging_configuration():
    monitor_script = os.path.join(MIGRATION_DIR, "monitor.py")
    assert os.path.isfile(monitor_script), f"Monitor script {monitor_script} does not exist."
    source = open(monitor_script, encoding="utf-8").read()
    tree = ast.parse(source, filename=monitor_script)

    matching_handler = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.id if isinstance(node.func, ast.Name) else (
            node.func.attr if isinstance(node.func, ast.Attribute) else "")
        if name != "RotatingFileHandler":
            continue
        values = {kw.arg: constant_number(kw.value) for kw in node.keywords if kw.arg}
        max_bytes = values.get("maxBytes")
        backup_count = values.get("backupCount")
        if max_bytes is None and len(node.args) > 2:
            max_bytes = constant_number(node.args[2])
        if backup_count is None and len(node.args) > 3:
            backup_count = constant_number(node.args[3])
        if max_bytes == 1024 and backup_count == 3:
            matching_handler = True
            break
    assert matching_handler, "monitor.py must use RotatingFileHandler(maxBytes=1024, backupCount=3)."
    assert "[%(asctime)s] - %(levelname)s - %(message)s" in source, \
        "The required logging format is not configured."
    assert "%Y-%m-%d %H:%M:%S" in source, "The required logging timestamp format is not configured."


def listener_loop(sock, stop_event):
    sock.settimeout(0.2)
    try:
        while not stop_event.is_set():
            try:
                conn, _ = sock.accept()
                conn.close()
            except socket.timeout:
                pass
    finally:
        sock.close()


def start_listeners(ports):
    stop_event = threading.Event()
    threads = []
    for port in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
            sock.listen(16)
        except Exception:
            sock.close()
            stop_event.set()
            for thread in threads:
                thread.join(timeout=2)
            raise AssertionError(f"Test could not control required backend port {port}; it is already in use.")
        thread = threading.Thread(target=listener_loop, args=(sock, stop_event), daemon=True)
        thread.start()
        threads.append(thread)
    return stop_event, threads


def clear_runtime_artifacts():
    for name in ("logs", "backups"):
        path = os.path.join(MIGRATION_DIR, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def run_monitor():
    monitor_script = os.path.join(MIGRATION_DIR, "monitor.py")
    result = subprocess.run(["python3", monitor_script, "--check"], capture_output=True, text=True,
                            timeout=15)
    assert result.returncode in (0, 1), f"monitor.py failed to execute:\n{result.stderr}"
    return result


def read_and_validate_log():
    log_file = os.path.join(MIGRATION_DIR, "logs", "monitor.log")
    assert os.path.isfile(log_file), f"Log file {log_file} was not created."
    with open(log_file, encoding="utf-8") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]
    assert lines, "monitor.log is empty."
    line_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] - (?:INFO|ERROR) - .+$")
    assert all(line_pattern.fullmatch(line) for line in lines), \
        f"Log lines do not use the required format: {lines!r}"
    return lines


def validate_backup(started):
    backups_dir = os.path.join(MIGRATION_DIR, "backups")
    assert os.path.isdir(backups_dir), f"Backups directory {backups_dir} was not created."
    backup_files = glob.glob(os.path.join(backups_dir, "apps_backup_*.tar.gz"))
    assert len(backup_files) == 1, f"Expected exactly one backup for one failed port, got {backup_files}."
    backup = backup_files[0]
    assert re.fullmatch(r"apps_backup_\d{8}_\d{6}\.tar\.gz", os.path.basename(backup)), \
        f"Backup filename has the wrong timestamp format: {backup}"
    assert os.path.getmtime(backup) >= started - 2, "Backup was not created by the current monitor run."

    with tarfile.open(backup, "r:gz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        found_apps = [name for name in names if "app1" in name or "app2" in name or "app3" in name]
        assert len(found_apps) >= 3, "Backup tarball does not contain the active_apps symlinks."
        for i in range(1, 4):
            candidates = [member for member in members
                          if member.name.rstrip("/").endswith(f"active_apps/app{i}")]
            assert candidates, f"Backup does not contain active_apps/app{i}."
            assert any(member.issym() for member in candidates), \
                f"active_apps/app{i} was not preserved as a symlink in the backup."


def test_monitor_script_logic():
    # Random order prevents a submission from relying on a fixed sequence. Every
    # single failed port and the all-healthy state are independently exercised.
    scenarios = [None] + PORTS[:]
    random.SystemRandom().shuffle(scenarios)

    for failed_port in scenarios:
        clear_runtime_artifacts()
        listening = PORTS if failed_port is None else [p for p in PORTS if p != failed_port]
        stop_event, threads = start_listeners(listening)
        try:
            started = time.time()
            run_monitor()
            lines = read_and_validate_log()
            text = "\n".join(lines)

            if failed_port is None:
                assert "INFO - All backend servers are healthy." in text, \
                    "The all-healthy message was not logged."
                assert "ERROR - Backend port" not in text, \
                    "A backend was reported down while all three ports were listening."
                backup_files = glob.glob(os.path.join(MIGRATION_DIR, "backups", "apps_backup_*.tar.gz"))
                assert not backup_files, "A backup was created even though all backends were healthy."
            else:
                expected = f"ERROR - Backend port {failed_port} is down. Initiating backup."
                assert expected in text, f"Log did not contain the expected error message: {expected}"
                for healthy_port in PORTS:
                    if healthy_port != failed_port:
                        assert f"Backend port {healthy_port} is down" not in text, \
                            f"Listening port {healthy_port} was incorrectly reported down."
                assert "All backend servers are healthy." not in text, \
                    "The healthy message was logged while a backend was down."
                validate_backup(started)
        finally:
            stop_event.set()
            for thread in threads:
                thread.join(timeout=2)


def test_monitor_rotates_log():
    clear_runtime_artifacts()
    stop_event, threads = start_listeners(PORTS)
    try:
        # Generate enough correctly formatted healthy messages to cross 1 KiB.
        for _ in range(25):
            run_monitor()
        log_dir = os.path.join(MIGRATION_DIR, "logs")
        assert os.path.isfile(os.path.join(log_dir, "monitor.log.1")), \
            "monitor.log did not rotate after exceeding 1024 bytes."
        numbered = glob.glob(os.path.join(log_dir, "monitor.log.[0-9]*"))
        suffixes = [int(path.rsplit(".", 1)[1]) for path in numbered]
        assert suffixes and max(suffixes) <= 3 and len(suffixes) <= 3, \
            f"More than 3 rotated backup logs were retained: {numbered}"
        for path in [os.path.join(log_dir, "monitor.log")] + numbered:
            assert os.path.getsize(path) <= 1100, f"Rotated log is unexpectedly larger than 1 KiB: {path}"
    finally:
        stop_event.set()
        for thread in threads:
            thread.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
