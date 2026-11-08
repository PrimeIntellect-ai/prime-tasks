#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import socket
import subprocess
import tarfile
import time
import pytest

HOST = "127.0.0.1"
PORT = 8080
EXTRACT_DIR = "/home/user/projects/extracted"
SOURCE_DIR = "/app/bash-backup-daemon-1.2.0"
INSTALL_DIR = "/home/user/daemon-bin"


def create_tar_gz(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, content in files.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))
    return buf.getvalue()


def send_payload(payload):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((HOST, PORT))
            s.sendall(payload)
            s.shutdown(socket.SHUT_WR)
            response = b""
            while True:
                data = s.recv(4096)
                if not data:
                    break
                response += data
        return response.decode("utf-8", errors="replace")
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to daemon on {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail("Socket connection timed out.")


def clean_extract_dir():
    if os.path.islink(EXTRACT_DIR):
        os.unlink(EXTRACT_DIR)
    elif os.path.exists(EXTRACT_DIR):
        shutil.rmtree(EXTRACT_DIR)
    os.makedirs(EXTRACT_DIR, exist_ok=True)
    os.chmod(EXTRACT_DIR, 0o777)


def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.append(int(pid))
                    break
        except OSError:
            continue
    return found


def test_package_configuration_and_local_install():
    makefile = os.path.join(SOURCE_DIR, "Makefile")
    config = os.path.join(SOURCE_DIR, "config.env.template")
    assert os.path.isfile(makefile), "Vendored Makefile is missing."
    assert os.path.isfile(config), "Vendored configuration is missing."

    result = subprocess.run(
        ["bash", "-c", 'set -e; cd "$1"; source ./config.env.template; printf "%s\\n%s\\n" "$DEST_DIR" "$PORT"', "bash", SOURCE_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"config.env.template cannot be sourced: {result.stderr}"
    assert result.stdout.splitlines() == [EXTRACT_DIR, "8080"], "DEST_DIR or PORT is configured incorrectly."

    install = subprocess.run(
        ["make", "-C", SOURCE_DIR, "install"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert install.returncode == 0, f"make install failed: {install.stdout}\n{install.stderr}"
    for script in ("extract_stream.sh", "start_daemon.sh"):
        path = os.path.join(INSTALL_DIR, script)
        assert os.path.isfile(path), f"{script} was not installed into {INSTALL_DIR}."
        assert os.access(path, os.X_OK), f"Installed {script} is not executable."


def test_builtin_socat_daemon_is_listening():
    pids = listening_pids(PORT)
    assert pids, f"No process is listening on TCP port {PORT}."
    matches = []
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        upper = cmdline.upper()
        if os.path.basename(exe) == "socat" and "LISTEN" in upper and "8080" in cmdline and "EXEC:" in upper and "extract_stream.sh" in cmdline:
            matches.append(pid)
    assert matches, "Port 8080 is not served by the package's socat/extract_stream.sh daemon."


def test_valid_archive():
    clean_extract_dir()
    payload = create_tar_gz({"project/file.txt": b"valid content"})
    send_payload(payload)
    extracted_file = os.path.join(EXTRACT_DIR, "project", "file.txt")
    time.sleep(0.5)
    assert os.path.isfile(extracted_file), f"Valid file was not extracted to {extracted_file}."
    with open(extracted_file, "rb") as f:
        assert f.read() == b"valid content", "Extracted file content mismatch."


def test_random_valid_archive_is_actually_extracted():
    clean_extract_dir()
    token = secrets.token_hex(12)
    content = secrets.token_bytes(73)
    relative = f"project-{token}/nested-{token}/payload.bin"
    send_payload(create_tar_gz({relative: content}))
    extracted = os.path.join(EXTRACT_DIR, relative)
    time.sleep(0.5)
    assert os.path.isfile(extracted), f"Random valid file was not extracted to {extracted}."
    with open(extracted, "rb") as f:
        assert f.read() == content, "Random extracted file content mismatch."


def test_malicious_archive_rejected():
    clean_extract_dir()
    hacked_file = "/home/user/hacked.txt"
    remove_path(hacked_file)
    payload = create_tar_gz({"project/../../home/user/hacked.txt": b"malicious content"})
    response = send_payload(payload)
    assert "ERROR: Path traversal detected" in response, (
        f"Expected exact error message 'ERROR: Path traversal detected', but got: {response}"
    )
    assert response.strip() == "ERROR: Path traversal detected", f"Unexpected rejection output: {response!r}"
    assert not os.path.exists(hacked_file), f"Malicious file was extracted to {hacked_file}!"


def test_absolute_path_malicious_archive_rejected():
    clean_extract_dir()
    hacked_file = "/tmp/absolute_hack.txt"
    remove_path(hacked_file)
    payload = create_tar_gz({"/tmp/absolute_hack.txt": b"absolute path content"})
    response = send_payload(payload)
    assert "ERROR: Path traversal detected" in response, (
        f"Expected exact error message 'ERROR: Path traversal detected' for absolute path, but got: {response}"
    )
    assert response.strip() == "ERROR: Path traversal detected", f"Unexpected rejection output: {response!r}"
    assert not os.path.exists(hacked_file), f"Malicious absolute path file was extracted to {hacked_file}!"


def test_random_mixed_traversal_archive_is_rejected_before_extraction():
    clean_extract_dir()
    token = secrets.token_hex(12)
    outside = f"/home/user/traversal-{token}.txt"
    remove_path(outside)
    benign_relative = f"benign-{token}/must-not-extract.txt"
    payload = create_tar_gz({
        benign_relative: secrets.token_bytes(31),
        f"project/../../../traversal-{token}.txt": secrets.token_bytes(47),
    })
    response = send_payload(payload)
    assert response.strip() == "ERROR: Path traversal detected", f"Unexpected rejection output: {response!r}"
    time.sleep(0.25)
    assert not os.path.exists(outside), f"Traversal payload created {outside}."
    assert not os.path.exists(os.path.join(EXTRACT_DIR, benign_relative)), "Archive was partially extracted before traversal rejection."


def test_random_absolute_path_is_rejected():
    clean_extract_dir()
    token = secrets.token_hex(12)
    outside = f"/tmp/absolute-{token}.bin"
    remove_path(outside)
    response = send_payload(create_tar_gz({outside: secrets.token_bytes(29)}))
    assert response.strip() == "ERROR: Path traversal detected", f"Unexpected rejection output: {response!r}"
    assert not os.path.exists(outside), f"Absolute archive member created {outside}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
