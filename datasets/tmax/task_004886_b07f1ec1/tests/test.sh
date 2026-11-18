#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import pytest

APP_ENV_DIR = "/home/user/app_env"
SOURCE_PATH = os.path.join(APP_ENV_DIR, "src", "backend.cpp")
BIN_PATH = os.path.join(APP_ENV_DIR, "bin", "backend")
SOCKET_PATH = os.path.join(APP_ENV_DIR, "run", "backend.sock")
FRONTEND_SOCKET = os.path.join(APP_ENV_DIR, "sockets", "upstream.sock")


def query_socket(path=FRONTEND_SOCKET):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        client.connect(path)
        client.sendall(b"STATUS\n")
        chunks = []
        while True:
            data = client.recv(1024)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks).decode("utf-8")
    finally:
        client.close()


def parse_exact_response(response):
    match = re.fullmatch(r"OK: ([0-9]+)\n", response)
    assert match, f"Daemon response was not exactly 'OK: <bytes>\\n': {response!r}"
    return int(match.group(1))


def socket_owner_pids(path):
    inodes = set()
    try:
        with open("/proc/net/unix", "r") as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[-1] == path:
                    inodes.add(fields[6])
    except OSError:
        return set()

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[([0-9]+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            continue
    return owners


def stop_socket_server():
    owners = socket_owner_pids(SOCKET_PATH)
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{p}") for p in owners):
        time.sleep(0.05)
    for pid in owners:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def start_backend(executable):
    proc = subprocess.Popen([executable], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read().decode("utf-8", errors="replace")
            pytest.fail(f"Backend {executable} exited before accepting connections: {stderr}")
        if os.path.exists(SOCKET_PATH):
            try:
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                probe.settimeout(0.2)
                probe.connect(SOCKET_PATH)
                probe.close()
                return proc
            except OSError:
                pass
        time.sleep(0.05)
    proc.kill()
    proc.wait(timeout=2)
    pytest.fail(f"Backend {executable} did not create a usable socket")


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass


def actual_available():
    statvfs = os.statvfs("/home/user")
    return statvfs.f_bavail * statvfs.f_frsize


def test_backup_exists_and_valid():
    backup_path = os.path.join(APP_ENV_DIR, "backups", "config_backup.tar.gz")
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            found_settings = any(name.endswith("settings.conf") for name in names)
            found_network = any(name.endswith("network.conf") for name in names)
            assert found_settings, "settings.conf not found in the backup tarball."
            assert found_network, "network.conf not found in the backup tarball."

            settings = [m for m in tar.getmembers() if m.isfile() and m.name.endswith("settings.conf")]
            network = [m for m in tar.getmembers() if m.isfile() and m.name.endswith("network.conf")]
            assert settings and network, "The backed-up configuration entries must be regular files."
            assert tar.extractfile(settings[0]).read() == b"daemon_mode=true\n", "Backed-up settings.conf has incorrect content."
            assert tar.extractfile(network[0]).read() == b"timeout=30\n", "Backed-up network.conf has incorrect content."
    except tarfile.TarError:
        pytest.fail(f"Backup file {backup_path} is not a valid gzip-compressed tarball.")


def test_symlink_fixed():
    symlink_path = os.path.join(APP_ENV_DIR, "sockets", "upstream.sock")
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    expected_target = "/home/user/app_env/run/backend.sock"
    assert target == expected_target, f"Symlink {symlink_path} points to {target} instead of {expected_target}."


def test_backend_compiled():
    assert os.path.isfile(BIN_PATH), f"Compiled executable {BIN_PATH} is missing."
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."


def test_verify_log_content():
    log_path = os.path.join(APP_ENV_DIR, "verify.log")
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    match = re.match(r"^OK:\s*(\d+)$", content)
    assert match, f"Log file {log_path} does not match the expected format 'OK: <bytes>'. Content: {content}"
    bytes_avail = int(match.group(1))
    assert bytes_avail > 0, "Available bytes reported in log should be greater than 0."

    with open(log_path, "rb") as f:
        raw = f.read()
    assert re.fullmatch(rb"OK: [0-9]+\n", raw), "verify.log must contain the exact query output, including its newline."


def test_backend_daemon_running_and_responds():
    assert os.path.exists(FRONTEND_SOCKET), f"Socket file {FRONTEND_SOCKET} does not exist. Is the daemon running?"
    try:
        response = query_socket()
    except Exception as e:
        pytest.fail(f"Failed to communicate with the daemon via {FRONTEND_SOCKET}: {e}")

    match = re.match(r"^OK:\s*(\d+)\n?$", response)
    assert match, f"Daemon response did not match 'OK: <bytes>\\n'. Response: {response}"
    reported_bytes = int(match.group(1))
    actual_avail = actual_available()
    margin = 50 * 1024 * 1024
    assert abs(reported_bytes - actual_avail) < margin, f"Reported bytes {reported_bytes} differs significantly from actual available bytes {actual_avail}."


def test_source_and_submitted_binary_are_real_dynamic_filesystem_backend():
    assert os.path.isfile(SOURCE_PATH), f"Backend source {SOURCE_PATH} is missing."
    source = open(SOURCE_PATH, "r", encoding="utf-8").read()
    source_without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", source, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"#\s*include\s*[<\"]filesystem[>\"]", source_without_comments), "backend.cpp must include <filesystem>."
    assert re.search(r"(?:std\s*::\s*)?filesystem\s*::\s*space\s*\(", source_without_comments), "backend.cpp must call std::filesystem::space."

    symbols = subprocess.run(["nm", "-C", BIN_PATH], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    assert symbols.returncode == 0, f"Could not inspect compiled backend: {symbols.stdout}"
    assert "std::filesystem::space" in symbols.stdout, "bin/backend does not contain a call to std::filesystem::space."

    stop_socket_server()
    proc = start_backend(BIN_PATH)
    allocation = os.path.join(APP_ENV_DIR, ".verifier_space_allocation")
    try:
        before_reported = parse_exact_response(query_socket())
        before_actual = actual_available()
        assert abs(before_reported - before_actual) < 8 * 1024 * 1024, "Submitted backend did not report current available space accurately."

        fd = os.open(allocation, os.O_CREAT | os.O_RDWR | os.O_TRUNC, 0o600)
        try:
            os.posix_fallocate(fd, 0, 64 * 1024 * 1024)
            os.fsync(fd)
        finally:
            os.close(fd)

        after_reported = parse_exact_response(query_socket())
        after_actual = actual_available()
        assert abs(after_reported - after_actual) < 8 * 1024 * 1024, "Submitted backend did not recompute available space after disk usage changed."
        assert before_reported - after_reported > 32 * 1024 * 1024, "Submitted backend appears to return a fixed or stale available-space value."
    finally:
        try:
            os.unlink(allocation)
        except FileNotFoundError:
            pass
        stop_process(proc)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "backend_from_source")
        build = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        assert build.returncode == 0, f"backend.cpp does not compile with g++ -std=c++17:\n{build.stdout}"
        rebuilt_proc = start_backend(rebuilt)
        try:
            reported = parse_exact_response(query_socket())
            assert abs(reported - actual_available()) < 8 * 1024 * 1024, "A fresh build of backend.cpp does not report current available space."
        finally:
            stop_process(rebuilt_proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
