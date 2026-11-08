#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import socket
import subprocess
import time
import tarfile
from decimal import Decimal


def request(host, port, payload, timeout=3):
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload.encode("ascii"))
        chunks = []
        while True:
            data = sock.recv(1024)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def wait_until(predicate, timeout, interval=0.2):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"Condition was not met within {timeout}s: {last_error}")
    raise AssertionError(f"Condition was not met within {timeout}s")


def test_rust_cost_analyzer():
    """Verify the Rust project builds and handles independently generated inputs."""
    project_dir = "/home/user/cost-analyzer"
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."

    build_result = subprocess.run(
        ["cargo", "build", "--release"], cwd=project_dir, capture_output=True
    )
    assert build_result.returncode == 0, (
        f"Failed to build Rust project: {build_result.stderr.decode()}"
    )

    binary_path = os.path.join(project_dir, "target", "release", "cost-analyzer")
    if not os.path.exists(binary_path):
        binary_path = os.path.join(project_dir, "target", "debug", "cost-analyzer")
    assert os.path.isfile(binary_path), "Compiled binary 'cost-analyzer' not found."

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    test_port = probe.getsockname()[1]
    probe.close()

    process = subprocess.Popen(
        [binary_path, str(test_port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_until(lambda: process.poll() is None and _port_accepts(test_port), 5)

        # Retain the original check and add unpredictable values whose results are
        # calculated by the verifier rather than embedded as trusted answers.
        values = [200]
        values.extend(random.SystemRandom().sample(range(1, 1000), 7))
        for value in values:
            expected = f"{Decimal(value) * Decimal('0.15'):.2f}\n".encode("ascii")
            response = request("127.0.0.1", test_port, f"{value}\n")
            assert response == expected, (
                f"For input {value}, expected {expected!r}, got {response!r}"
            )
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def _port_accepts(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


def _parse_haproxy(content):
    sections = []
    current = None
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if parts[0].lower() in {"global", "defaults", "frontend", "backend", "listen"}:
            current = {
                "kind": parts[0].lower(),
                "name": parts[1] if len(parts) > 1 else "",
                "header": parts[2:],
                "directives": [],
            }
            sections.append(current)
        elif current is not None:
            current["directives"].append((parts[0].lower(), parts[1:]))
    return sections


def _directive_values(section, keyword):
    return [args for key, args in section["directives"] if key == keyword]


def test_haproxy_cfg():
    """Verify syntax and the requested TCP round-robin proxy semantics."""
    cfg_path = "/home/user/haproxy.cfg"
    assert os.path.isfile(cfg_path), f"HAProxy config {cfg_path} does not exist."

    with open(cfg_path, "r") as f:
        content = f.read()

    # Preserve the original endpoint assertions.
    assert "127.0.0.1:8080" in content, "HAProxy config missing listen on 127.0.0.1:8080"
    assert "127.0.0.1:8081" in content, "HAProxy config missing backend 127.0.0.1:8081"
    assert "127.0.0.1:8082" in content, "HAProxy config missing backend 127.0.0.1:8082"
    assert "127.0.0.1:8083" in content, "HAProxy config missing backend 127.0.0.1:8083"

    result = subprocess.run(["haproxy", "-c", "-f", cfg_path], capture_output=True)
    assert result.returncode == 0, f"HAProxy config is invalid: {result.stderr.decode()}"

    sections = _parse_haproxy(content)
    default_tcp = any(
        args and args[0].lower() == "tcp"
        for section in sections if section["kind"] == "defaults"
        for args in _directive_values(section, "mode")
    )

    serving = None
    for section in sections:
        if section["kind"] not in {"frontend", "listen"}:
            continue
        addresses = list(section["header"])
        for args in _directive_values(section, "bind"):
            addresses.extend(args)
        if any("127.0.0.1:8080" in item for item in addresses):
            serving = section
            break
    assert serving is not None, "No frontend/listen section binds 127.0.0.1:8080"

    explicit_tcp = any(
        args and args[0].lower() == "tcp" for args in _directive_values(serving, "mode")
    )
    assert explicit_tcp or default_tcp, "The proxy listening on 8080 is not in TCP mode"

    if serving["kind"] == "listen":
        backend = serving
    else:
        defaults = _directive_values(serving, "default_backend")
        assert defaults and defaults[0], "The 8080 frontend has no default backend"
        backend_name = defaults[0][0]
        backend = next(
            (s for s in sections if s["kind"] == "backend" and s["name"] == backend_name),
            None,
        )
        assert backend is not None, f"Referenced backend {backend_name!r} does not exist"

    backend_tcp = any(
        args and args[0].lower() == "tcp" for args in _directive_values(backend, "mode")
    )
    assert backend_tcp or default_tcp, "The selected backend is not in TCP mode"

    balances = _directive_values(backend, "balance")
    assert any(args and args[0].lower() == "roundrobin" for args in balances), (
        "The selected backend does not use roundrobin balancing"
    )

    server_targets = []
    for args in _directive_values(backend, "server"):
        if len(args) >= 2:
            server_targets.append(args[1])
    expected = {
        "127.0.0.1:8081",
        "127.0.0.1:8082",
        "127.0.0.1:8083",
    }
    assert expected.issubset(set(server_targets)), (
        f"Selected backend server targets are incomplete: {server_targets}"
    )


def _matching_backend_pids(binary_path, port, pgid):
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.getpgid(pid) != pgid:
                continue
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if not os.path.samefile(exe, binary_path):
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if str(port) in args:
                matches.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass
    return matches


def _matching_haproxy_pids(cfg_path, pgid):
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.getpgid(pid) != pgid:
                continue
            exe = os.path.basename(os.path.realpath(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if exe.startswith("haproxy") and cfg_path in args:
                matches.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass
    return matches


def test_supervisor_script():
    """Execute the supervisor and verify startup, proxying, and backend restart."""
    script_path = "/home/user/supervisor.sh"
    cfg_path = "/home/user/haproxy.cfg"
    binary_path = "/home/user/cost-analyzer/target/release/cost-analyzer"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert os.path.isfile(binary_path), "Release cost-analyzer binary is missing"

    with open(script_path, "r") as f:
        content = f.read()
    assert re.search(r'\b(while|for|until)\b', content), (
        "supervisor.sh does not contain a loop for monitoring."
    )
    assert "8081" in content and "8082" in content and "8083" in content, (
        "supervisor.sh does not reference the expected ports."
    )

    supervisor = subprocess.Popen(
        [script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    pgid = supervisor.pid
    try:
        def all_started():
            if supervisor.poll() is not None:
                return False
            backend_sets = [
                _matching_backend_pids(binary_path, port, pgid)
                for port in (8081, 8082, 8083)
            ]
            return all(len(pids) == 1 for pids in backend_sets) and bool(
                _matching_haproxy_pids(cfg_path, pgid)
            )

        wait_until(all_started, 10)

        for port in (8081, 8082, 8083):
            assert request("127.0.0.1", port, "40\n") == b"6.00\n"
        assert request("127.0.0.1", 8080, "60\n") == b"9.00\n", (
            "HAProxy did not proxy a calculation through the configured frontend"
        )

        old_pid = _matching_backend_pids(binary_path, 8082, pgid)[0]
        os.kill(old_pid, signal.SIGKILL)

        def restarted():
            if supervisor.poll() is not None:
                return False
            pids = _matching_backend_pids(binary_path, 8082, pgid)
            return len(pids) == 1 and pids[0] != old_pid

        wait_until(restarted, 12)
        assert request("127.0.0.1", 8082, "80\n") == b"12.00\n", (
            "The restarted backend on port 8082 is not functional"
        )
    finally:
        try:
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            supervisor.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            supervisor.wait(timeout=3)


def test_fstab_entry():
    """Verify the fstab fields and required options without imposing option order."""
    fstab_path = "/home/user/fstab_entry.txt"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read()
    lines = content.splitlines()
    assert len(lines) == 1 and lines[0].strip(), "fstab_entry.txt must contain exactly one line"

    fields = lines[0].split()
    assert len(fields) == 6, f"fstab entry must have six fields. Got: {lines[0]}"
    source, mountpoint, filesystem, option_text, dump, passno = fields
    assert source == "tmpfs", f"Expected tmpfs source, got {source}"
    assert mountpoint == "/home/user/reports", f"Unexpected mountpoint: {mountpoint}"
    assert filesystem == "tmpfs", f"Expected tmpfs filesystem, got {filesystem}"
    options = set(option_text.split(","))
    assert "size=50M" in options, "fstab options missing size=50M"
    assert "uid=1000" in options, "fstab options missing uid=1000"
    assert "gid=1000" in options, "fstab options missing gid=1000"
    assert dump == "0" and passno == "0", "fstab dump/pass fields must be 0 0"


def test_backup_script():
    """Verify the backup script creates a valid compressed archive."""
    script_path = "/home/user/backup.sh"
    reports_dir = "/home/user/reports"
    backups_dir = "/home/user/backups"
    archive_path = os.path.join(backups_dir, "reports_backup.tar.gz")

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    os.makedirs(reports_dir, exist_ok=True)
    dummy_file = os.path.join(reports_dir, "test.txt")
    with open(dummy_file, "w") as f:
        f.write("dummy content")

    result = subprocess.run([script_path], capture_output=True)
    assert result.returncode == 0, f"Backup script failed: {result.stderr.decode()}"
    assert os.path.isfile(archive_path), f"Backup archive {archive_path} was not created."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any(name.endswith("test.txt") for name in names), (
            "test.txt not found in backup archive."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
