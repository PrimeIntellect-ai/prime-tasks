#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_restore_automation.py
import json
import os
import signal
import socket
import stat
import subprocess
import tarfile
import threading
import time
import uuid

SCRIPT = "/home/user/restore_automation.py"
FETCH = "/home/user/tools/fetch_backup"
BACKUP = "/home/user/backup.tar"
MOUNT = "/home/user/mnt_restore"
FSTAB = "/home/user/mock_root/etc/fstab"
PASSWD = "/home/user/mock_root/etc/passwd"
STATUS = "/home/user/restore_status.log"
EXPECTED_FSTAB = "/home/user/backup.tar /home/user/mnt_restore tarfs ro,nosuid,nodev 0 0"


def install_fetch(username, marker):
    program = f'''#!/usr/bin/env python3
import json
import os
import sys
import tarfile

print("Operator PIN: ", end="", flush=True)
pin = sys.stdin.readline().strip()
if pin == "8374" and sys.stdin.isatty():
    print("Success")
    with open("/home/user/metadata.json", "w") as f:
        json.dump({{"username": {username!r}}}, f)
    with tarfile.open("/home/user/backup.tar", "w") as tar:
        tar.add("/home/user/metadata.json", arcname="metadata.json")
    with open({marker!r}, "w") as f:
        f.write("authenticated")
    sys.exit(0)
print("Failed")
sys.exit(1)
'''
    with open(FETCH, "w") as f:
        f.write(program)
    os.chmod(FETCH, 0o755)


def reset_state(username, marker):
    for path in (BACKUP, STATUS, "/home/user/metadata.json", marker):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    os.makedirs(MOUNT, exist_ok=True)
    for name in os.listdir(MOUNT):
        path = os.path.join(MOUNT, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    with open(FSTAB, "w") as f:
        f.write("/dev/sda1 / ext4 defaults 1 1\n")
    with open(PASSWD, "w") as f:
        f.write("root:x:0:0:root:/root:/bin/bash\n")
        f.write("user:x:1000:1000:user:/home/user:/bin/bash\n")
        f.write(f"{username}:x:1001:1001:Backup User:/home/{username}:/bin/bash\n")
    install_fetch(username, marker)


def stop_process(proc):
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
            proc.wait(timeout=2)


class Backend:
    def __init__(self):
        self.received = []
        self.stop_event = threading.Event()
        self.ready = threading.Event()
        self.sock = None
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()
        assert self.ready.wait(3), "Mock service on port 8080 did not start"

    def run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock = sock
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("127.0.0.1", 8080))
        sock.listen(20)
        sock.settimeout(0.2)
        self.ready.set()
        while not self.stop_event.is_set():
            try:
                conn, addr = sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self.handle, args=(conn, addr), daemon=True).start()

    def handle(self, conn, addr):
        with conn:
            conn.settimeout(2)
            try:
                data = conn.recv(65536)
            except (socket.timeout, OSError):
                return
            if data:
                self.received.append(data)
                try:
                    conn.sendall(b"BACKEND:" + data)
                except OSError:
                    pass

    def stop(self):
        self.stop_event.set()
        if self.sock is not None:
            self.sock.close()
        self.thread.join(timeout=2)


def connect_proxy(source_ip, payload, deadline):
    last_error = None
    while time.monotonic() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.bind((source_ip, 0))
            sock.connect(("127.0.0.1", 9999))
            sock.sendall(payload)
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
            time.sleep(0.05)
    raise AssertionError(f"Proxy did not become available on 127.0.0.1:9999: {last_error}")


def assert_archive_and_extraction(username):
    # Original artifact assertions.
    assert os.path.isfile(BACKUP), f"Expected backup archive at {BACKUP} is missing. Did the script successfully interact with fetch_backup?"
    metadata_path = os.path.join(MOUNT, "metadata.json")
    assert os.path.isfile(metadata_path), f"Expected extracted file at {metadata_path} is missing. Did the script extract the tarball?"

    assert stat.S_ISREG(os.lstat(BACKUP).st_mode), "backup.tar must be a regular file"
    assert tarfile.is_tarfile(BACKUP), "backup.tar is not a valid tar archive"
    with tarfile.open(BACKUP, "r") as tar:
        member = tar.getmember("metadata.json")
        archived = json.load(tar.extractfile(member))
    with open(metadata_path) as f:
        extracted = json.load(f)
    assert archived == {"username": username}
    assert extracted == archived, "Extracted metadata does not match the authenticated backup archive"


def assert_original_final_state(username):
    assert_archive_and_extraction(username)

    assert os.path.isfile(FSTAB), f"File {FSTAB} is missing."
    with open(FSTAB) as f:
        content = f.read()
    assert EXPECTED_FSTAB in content, "The fstab file does not contain the expected backup mount entry."
    assert "/dev/sda1" in content, "The original contents of the fstab file were not preserved."

    assert os.path.isfile(STATUS), f"Log file {STATUS} is missing."
    with open(STATUS) as f:
        status = f.read().strip()
    assert status == "USER_VERIFIED: backup_admin", f"Expected log content 'USER_VERIFIED: backup_admin', but got '{status}'."


def test_complete_restore_pipeline_and_proxy():
    assert os.path.isfile(SCRIPT), f"The automation script {SCRIPT} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), "restore_automation.py must be a regular file"
    with open(SCRIPT) as f:
        source = f.read()
    assert "9999" in source, "The script does not seem to contain the proxy listening port 9999."
    assert "8080" in source, "The script does not seem to contain the proxy destination port 8080."
    assert "pexpect" in source, "The script must use pexpect for the interactive authentication step."

    marker = f"/tmp/fetch_marker_{uuid.uuid4().hex}"
    reset_state("backup_admin", marker)
    backend = Backend()
    backend.start()
    proc = subprocess.Popen(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        allowed_token = ("allowed-" + uuid.uuid4().hex).encode()
        allowed = connect_proxy("127.0.0.1", allowed_token, time.monotonic() + 8)
        proxy_ready_at = time.monotonic()
        with allowed:
            response = allowed.recv(65536)
        assert response == b"BACKEND:" + allowed_token, "Proxy did not forward traffic bidirectionally to port 8080"

        forbidden_token = ("forbidden-" + uuid.uuid4().hex).encode()
        forbidden = connect_proxy("127.0.0.2", forbidden_token, time.monotonic() + 2)
        with forbidden:
            forbidden.settimeout(2)
            try:
                blocked_response = forbidden.recv(65536)
            except socket.timeout:
                raise AssertionError("Non-127.0.0.1 client was not gracefully closed")
        assert blocked_response == b"", "A client whose source IP is not exactly 127.0.0.1 was not rejected"
        time.sleep(0.3)
        assert all(forbidden_token not in data for data in backend.received), "Forbidden traffic reached the backend service"

        deadline = proxy_ready_at + 5.0
        while time.monotonic() < deadline:
            assert proc.poll() is None, "The script exited before keeping the proxy alive for five seconds"
            time.sleep(0.05)

        assert os.path.isfile(marker), "fetch_backup was not successfully authenticated through an interactive terminal"
        assert_original_final_state("backup_admin")
    finally:
        stop_process(proc)
        backend.stop()

    # Exercise the restore again with verifier-derived metadata so hardcoded files
    # and a hardcoded status string cannot satisfy the behavioral checks.
    dynamic_user = "restore_" + uuid.uuid4().hex[:12]
    dynamic_marker = f"/tmp/fetch_marker_{uuid.uuid4().hex}"
    reset_state(dynamic_user, dynamic_marker)
    proc = subprocess.Popen(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 10
        expected_status = f"USER_VERIFIED: {dynamic_user}"
        while time.monotonic() < deadline:
            if os.path.isfile(dynamic_marker) and os.path.isfile(STATUS) and os.path.isfile(BACKUP):
                with open(STATUS) as f:
                    if f.read().strip() == expected_status:
                        break
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                raise AssertionError(f"Dynamic restore run exited early ({proc.returncode}). stdout={stdout!r} stderr={stderr!r}")
            time.sleep(0.05)
        else:
            raise AssertionError("Dynamic restore run did not authenticate, extract, and verify the generated user")

        assert os.path.isfile(dynamic_marker), "The dynamic fetch tool was not interactively authenticated"
        assert_archive_and_extraction(dynamic_user)
        with open(STATUS) as f:
            assert f.read().strip() == expected_status
        with open(FSTAB) as f:
            fstab_content = f.read()
        assert EXPECTED_FSTAB in fstab_content
        assert "/dev/sda1" in fstab_content
    finally:
        stop_process(proc)
TEST_EOF

if python3 -m pytest /tmp/test_restore_automation.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
