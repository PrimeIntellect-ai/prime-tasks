#!/bin/bash
set -e
mkdir -p /logs/verifier

# Supply the SSH service and mock receiver that the environment promised.
service ssh start >/dev/null 2>&1 || true
service cron stop >/dev/null 2>&1 || true

cat > /tmp/verify_backup.py <<'PY'
import gzip
import io
import json
import os
import signal
import socket
import subprocess
import tarfile
import tempfile
import threading
import time

PROJECT = "/home/user/backup_agent"
RELEASE = os.path.join(PROJECT, "target", "release")
RECEIVED = "/home/user/received_backup.dat"
LOCAL_PORT = 5050
SERVER_PORT = 8443
LIMIT = 50000


def run_as_user(args, timeout=180, env=None):
    cmd = ["sudo", "-u", "user"]
    if env:
        cmd += ["env"] + [f"{k}={v}" for k, v in env.items()]
    cmd += args
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout)


def listening_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def processes_for_inodes(inodes):
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    result.append(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def assert_ssh_tunnel():
    # Preserve the original active-port assertion.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3)
        assert s.connect_ex(("localhost", LOCAL_PORT)) == 0, \
            "SSH tunnel is not listening on port 5050"

    pids = processes_for_inodes(listening_inodes(LOCAL_PORT))
    assert pids, "No process owns the listener on port 5050"
    matches = []
    for pid in pids:
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except OSError:
            continue
        command = " ".join(argv)
        if exe == "ssh" and "-L" in argv and "5050:localhost:8443" in command:
            matches.append(pid)
    assert matches, "Port 5050 must be owned by an ssh -L tunnel forwarding to localhost:8443"


def read_cron():
    result = subprocess.run(["crontab", "-l", "-u", "user"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, "No crontab found for user"
    assert result.stdout.strip(), "User crontab is empty"
    return [line.strip() for line in result.stdout.splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def cargo_binaries():
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), "Cargo.toml is missing from the Rust project"
    result = run_as_user(["cargo", "metadata", "--offline", "--no-deps",
                          "--format-version", "1", "--manifest-path", manifest])
    assert result.returncode == 0, f"Invalid Cargo project: {result.stderr}"
    metadata = json.loads(result.stdout)
    project_manifest = os.path.realpath(manifest)
    names = []
    for package in metadata["packages"]:
        if os.path.realpath(package["manifest_path"]) == project_manifest:
            for target in package["targets"]:
                if "bin" in target.get("kind", []):
                    names.append(target["name"])
    assert names, "Cargo project has no Rust binary target"
    return names


def check_release_and_cron():
    # Preserve the original release-directory and executable assertions.
    assert os.path.isdir(RELEASE), f"Rust release directory not found at {RELEASE}"
    executables = []
    for root, _, files in os.walk(RELEASE):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.isfile(path) and os.access(path, os.X_OK) and not filename.endswith(".d"):
                executables.append(path)
    assert executables, "No executable found in the Rust release directory"

    cron_lines = read_cron()
    candidates = [os.path.join(RELEASE, name) for name in cargo_binaries()]
    scheduled = []
    for line in cron_lines:
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"]:
            for candidate in candidates:
                if candidate in fields[5]:
                    scheduled.append(candidate)
    assert scheduled, "Crontab must run the compiled Cargo release binary every minute"
    binary = scheduled[0]
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
        "The scheduled release binary does not exist or is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The scheduled release artifact is not a native executable"
    return binary, os.path.basename(binary)


def kill_server_port_listeners():
    for pid in processes_for_inodes(listening_inodes(SERVER_PORT)):
        if pid not in (1, os.getpid()):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listening_inodes(SERVER_PORT) and time.time() < deadline:
        time.sleep(0.1)
    for pid in processes_for_inodes(listening_inodes(SERVER_PORT)):
        if pid not in (1, os.getpid()):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def capture_execution(binary):
    captured = []
    errors = []
    ready = threading.Event()

    def receiver():
        server = None
        try:
            try:
                server = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
                server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("::", SERVER_PORT))
            except OSError:
                if server is not None:
                    server.close()
                server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", SERVER_PORT))
            server.listen(1)
            server.settimeout(45)
            ready.set()
            conn, _ = server.accept()
            with conn:
                conn.settimeout(20)
                chunks = []
                while True:
                    data = conn.recv(65536)
                    if not data:
                        break
                    chunks.append(data)
                captured.append(b"".join(chunks))
        except Exception as exc:
            errors.append(repr(exc))
            ready.set()
        finally:
            if server is not None:
                server.close()

    thread = threading.Thread(target=receiver, daemon=True)
    thread.start()
    assert ready.wait(5), "Mock backup listener did not start"
    assert not errors, f"Mock backup listener failed: {errors}"
    result = run_as_user([binary], timeout=90,
                         env={"HOME": "/home/user", "USER": "user"})
    thread.join(50)
    assert not thread.is_alive(), "Backup connection was not gracefully closed"
    assert result.returncode == 0, \
        f"Backup binary failed with exit code {result.returncode}: {result.stderr}"
    assert not errors, f"Mock backup listener failed: {errors}"
    assert len(captured) == 1, "Backup binary did not transmit one payload through the tunnel"
    return captured[0]


def expected_files():
    root = "/home/user/telemetry_data"
    expected = {}
    for base, _, files in os.walk(root):
        for filename in files:
            path = os.path.join(base, filename)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, "rb") as f:
                expected[rel] = f.read()
    assert expected, "Telemetry directory is empty"
    return expected


def validate_payload(payload):
    # Preserve and strengthen the original received-payload size assertions.
    assert len(payload) > 0, "Received backup payload is empty"
    assert len(payload) <= LIMIT, \
        f"Compression insufficient: received {len(payload)} bytes, limit is {LIMIT}"
    assert payload.startswith(b"\x1f\x8b"), "Transferred payload is not a GZIP stream"

    expected = expected_files()
    try:
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
            actual = {}
            for member in archive.getmembers():
                if not member.isfile():
                    continue
                normalized = member.name.lstrip("./")
                matches = [rel for rel in expected
                           if normalized == rel or normalized.endswith("/" + rel)]
                assert len(matches) == 1, f"Unexpected file in backup archive: {member.name}"
                rel = matches[0]
                assert rel not in actual, f"Duplicate telemetry file in archive: {rel}"
                extracted = archive.extractfile(member)
                assert extracted is not None
                actual[rel] = extracted.read()
            assert actual == expected, "Tar/GZIP payload does not contain all telemetry files exactly"
            return
    except tarfile.ReadError:
        pass

    raw = gzip.decompress(payload)
    concatenated = b"".join(expected[name] for name in sorted(expected))
    assert raw == concatenated, \
        "Plain GZIP payload does not contain the complete telemetry data"


assert_ssh_tunnel()
installed_binary, binary_name = check_release_and_cron()
kill_server_port_listeners()

# Execute the exact artifact named by cron and validate what arrives through 5050 -> 8443.
installed_payload = capture_execution(installed_binary)
validate_payload(installed_payload)

# Rebuild independently to ensure the submitted Cargo/Rust source implements the same task.
target_dir = tempfile.mkdtemp(prefix="backup-agent-verify-")
os.chown(target_dir, 1000, 1000)
build = run_as_user(["cargo", "build", "--release", "--offline",
                     "--manifest-path", os.path.join(PROJECT, "Cargo.toml"),
                     "--target-dir", target_dir], timeout=240,
                    env={"HOME": "/home/user", "USER": "user"})
assert build.returncode == 0, f"Rust project does not build in release mode: {build.stderr}"
rebuilt_binary = os.path.join(target_dir, "release", binary_name)
assert os.path.isfile(rebuilt_binary) and os.access(rebuilt_binary, os.X_OK), \
    "Independent release build did not produce the scheduled binary"
rebuilt_payload = capture_execution(rebuilt_binary)
validate_payload(rebuilt_payload)

with open(RECEIVED, "wb") as f:
    f.write(installed_payload)
os.chown(RECEIVED, 1000, 1000)
assert os.path.isfile(RECEIVED)
assert 0 < os.path.getsize(RECEIVED) <= LIMIT
PY

if python3 /tmp/verify_backup.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
