#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pwd
import re
import shlex
import socket
import ssl
import subprocess
import time
import urllib.request
import zipfile
from pathlib import Path

import pytest

USER = "user"
HOME = Path("/home/user")
PROJECT = HOME / "app/health-server"
BINARY = PROJECT / "target/release/health-server"
UNIT = HOME / ".config/systemd/user/health-server.service"
ARCHIVE = HOME / "certs.zip"
MOUNTPOINT = HOME / "app/certs"
EXPECTED_BODY = b'{"status": "healthy"}'


def user_command(args, timeout=60):
    uid = pwd.getpwnam(USER).pw_uid
    runtime = f"/run/user/{uid}"
    env_args = [
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
        "HOME=/home/user",
        "USER=user",
    ]
    return subprocess.run(
        ["runuser", "-u", USER, "--", "env", *env_args, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def systemctl(*args, timeout=60):
    return user_command(["systemctl", "--user", *args], timeout=timeout)


def assert_ok(result, description):
    assert result.returncode == 0, (
        f"{description} failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def command_entries(prop):
    result = systemctl("show", "health-server.service", f"--property={prop}", "--value")
    assert_ok(result, f"reading {prop}")
    entries = []
    for block in re.findall(r"\{([^{}]+)\}", result.stdout):
        path_match = re.search(r"(?:^|;\s*)path=(.*?)\s*;\s*argv\[\]=(.*?)\s*;\s*ignore_errors=", block)
        if path_match:
            path = path_match.group(1).strip()
            argv = shlex.split(path_match.group(2).strip())
            entries.append((path, argv))
    return entries


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_restart_service():
    assert UNIT.is_file(), f"Service file not found at {UNIT}"
    assert BINARY.is_file(), "Release binary was not built by the agent"
    assert not BINARY.is_symlink(), "Release artifact must be a real compiled binary"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "Release artifact is not an ELF binary"

    assert_ok(systemctl("daemon-reload"), "systemd user daemon reload")

    # Rebuild the submitted Rust source, then restart through the submitted unit.
    build = user_command(["cargo", "build", "--release", "--locked"], timeout=240)
    if build.returncode != 0 and "lock file" in build.stderr.lower():
        build = user_command(["cargo", "build", "--release"], timeout=240)
    assert_ok(build, "Rust release build")
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "Cargo did not produce an ELF binary"

    assert_ok(systemctl("restart", "health-server.service"), "service restart")
    for _ in range(30):
        active = systemctl("is-active", "health-server.service")
        if active.stdout.strip() == "active":
            break
        time.sleep(0.2)
    assert active.stdout.strip() == "active", (
        f"health-server.service is not active: {active.stdout} {active.stderr}"
    )


def test_systemd_service_configuration():
    """Check effective directives, not comments containing command names."""
    starts = command_entries("ExecStart")
    assert len(starts) == 1, "Service must have one effective ExecStart"
    start_path, start_argv = starts[0]
    assert Path(start_path).resolve() == BINARY.resolve(), "ExecStart does not run the Rust release binary"
    assert start_argv and Path(start_argv[0]).resolve() == BINARY.resolve(), "ExecStart argv is incorrect"

    pre = command_entries("ExecStartPre")
    mount_commands = []
    for path, argv in pre:
        if Path(path).name == "archivemount" and argv:
            mount_commands.append(argv)
    assert mount_commands, "No effective ExecStartPre invokes archivemount"
    assert any(
        str(ARCHIVE) in argv and str(MOUNTPOINT) in argv
        and argv.index(str(ARCHIVE)) < argv.index(str(MOUNTPOINT))
        for argv in mount_commands
    ), "archivemount must mount /home/user/certs.zip at /home/user/app/certs"

    stop_commands = command_entries("ExecStop") + command_entries("ExecStopPost")
    valid_unmount = False
    for path, argv in stop_commands:
        if Path(path).name in {"fusermount", "fusermount3"}:
            valid_unmount |= "-u" in argv and str(MOUNTPOINT) in argv
    assert valid_unmount, "No effective stop directive runs fusermount -u on the certificate mount"


def test_archive_is_actually_mounted():
    result = subprocess.run(
        ["findmnt", "-rn", "-M", str(MOUNTPOINT), "-o", "TARGET,SOURCE,FSTYPE"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Certificate directory is not a mount point: {result.stderr}"
    fields = result.stdout.strip().split()
    assert len(fields) >= 3 and fields[0] == str(MOUNTPOINT), "Wrong certificate mount target"
    source, fstype = fields[1], fields[2]
    assert "archivemount" in fstype.lower(), f"Mount is not provided by archivemount: {fstype}"
    assert source == str(ARCHIVE) or "archivemount" in source.lower(), "Unexpected archive mount source"

    with zipfile.ZipFile(ARCHIVE) as zf:
        cert_names = [n for n in zf.namelist() if n.endswith("/cert.pem") or n == "cert.pem"]
        key_names = [n for n in zf.namelist() if n.endswith("/key.pem") or n == "key.pem"]
        assert cert_names and key_names, "Certificate archive is invalid"
        archived_cert = zf.read(cert_names[0])
        archived_key = zf.read(key_names[0])

    mounted_certs = list(MOUNTPOINT.rglob("cert.pem"))
    mounted_keys = list(MOUNTPOINT.rglob("key.pem"))
    assert any(p.read_bytes() == archived_cert for p in mounted_certs), "Mounted certificate is not from certs.zip"
    assert any(p.read_bytes() == archived_key for p in mounted_keys), "Mounted key is not from certs.zip"


def test_systemd_service_active_and_runs_binary():
    active = systemctl("is-active", "health-server.service")
    assert active.stdout.strip() == "active", "health-server.service is not active"

    pid_result = systemctl("show", "health-server.service", "--property=MainPID", "--value")
    assert_ok(pid_result, "reading service MainPID")
    pid = int(pid_result.stdout.strip())
    assert pid > 0, "Service has no main process"
    assert os.stat(f"/proc/{pid}").st_uid == pwd.getpwnam(USER).pw_uid, "Service is not running as user"
    assert Path(f"/proc/{pid}/exe").resolve() == BINARY.resolve(), "Service main process is not the Rust binary"

    listeners = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        for line in Path(table).read_text().splitlines()[1:]:
            cols = line.split()
            if len(cols) >= 10 and cols[3] == "0A":
                host, port = cols[1].split(":")
                if int(port, 16) == 8443:
                    listeners.append((table, host, cols[9]))
    assert listeners, "Nothing is listening on port 8443"
    assert any(table.endswith("tcp") and host == "0100007F" for table, host, _ in listeners), (
        "Server is not bound specifically to IPv4 127.0.0.1:8443"
    )
    service_fds = set()
    for fd in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            service_fds.add(match.group(1))
    assert any(inode in service_fds for _, _, inode in listeners), (
        "Port 8443 is not owned by the service's Rust process"
    )


def fetch_health():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://127.0.0.1:8443/health")
    with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
        return response.status, response.read()


def test_endpoint_is_reachable_with_exact_body():
    status, body = fetch_health()
    assert status == 200, f"Expected HTTP 200, got {status}"
    data = json.loads(body.decode("utf-8"))
    assert data.get("status") == "healthy", "Endpoint did not return healthy status"
    assert data == {"status": "healthy"}, "Endpoint JSON contains missing or extra fields"
    assert body == EXPECTED_BODY, f"Endpoint body is not exact: {body!r}"

    # Confirm TLS uses the certificate supplied by the mounted archive.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls:
            peer_der = tls.getpeercert(binary_form=True)
    with zipfile.ZipFile(ARCHIVE) as zf:
        cert_name = next(n for n in zf.namelist() if n.endswith("/cert.pem") or n == "cert.pem")
        pem = zf.read(cert_name).decode("ascii")
    archive_der = base64.b64decode(ssl.PEM_cert_to_DER_cert(pem))
    assert peer_der == archive_der, "Server is not using the certificate from certs.zip"


def test_health_output_file():
    output_file = HOME / "health_output.json"
    assert output_file.is_file(), f"Output file not found at {output_file}"
    content = output_file.read_bytes()
    data = json.loads(content.decode("utf-8"))
    assert data.get("status") == "healthy", "Saved JSON does not contain healthy status"
    assert data == {"status": "healthy"}, "Saved JSON contains missing or extra fields"
    assert content == EXPECTED_BODY, f"Saved curl stdout is not exact: {content!r}"

    curl = subprocess.run(
        ["curl", "-k", "--silent", "--show-error", "--max-time", "5", "https://127.0.0.1:8443/health"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert curl.returncode == 0, f"curl failed: {curl.stderr.decode(errors='replace')}"
    assert curl.stdout == content == EXPECTED_BODY, "health_output.json is not the exact curl stdout"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
