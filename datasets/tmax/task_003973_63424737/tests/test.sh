#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import socket
import subprocess
import tempfile
import threading

import pytest
import requests

RESTORED_DIR = "/home/user/restored_data"
MANIFEST_PATH = os.path.join(RESTORED_DIR, "manifest.json")
DATA_CSV_PATH = os.path.join(RESTORED_DIR, "data.csv")
LOG_PATH = "/home/user/restore_drill.log"
SERVER_URL = "http://127.0.0.1:8080"
RESTORE_AGENT = "/app/restore_agent"
BACKUP_PATH = "/app/backup.dat"


def stop_existing_health_listener():
    """Free the drill's reserved health port if an old daemon was left running."""
    inodes = set()
    try:
        with open("/proc/net/tcp", "r", encoding="ascii") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                port = int(local_address.split(":")[1], 16)
                if port == 7777 and state == "0A":
                    inodes.add(fields[9])
    except OSError:
        return

    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if any(target == f"socket:[{inode}]" for inode in inodes):
                    try:
                        os.kill(int(entry), 15)
                    except (OSError, ValueError):
                        pass
                    break
        except OSError:
            continue


@pytest.fixture(scope="session")
def oracle_restore():
    assert os.path.isfile(RESTORE_AGENT), f"Restore agent missing: {RESTORE_AGENT}"
    assert os.access(RESTORE_AGENT, os.X_OK), "Restore agent is not executable"
    with open(RESTORE_AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Restore agent is not an ELF executable"
    assert os.path.isfile(BACKUP_PATH), f"Backup archive missing: {BACKUP_PATH}"

    stop_existing_health_listener()

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 7777))
    listener.listen(1)
    listener.settimeout(5)
    exchange = {}

    def health_service():
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(5)
            received = b""
            while not received.endswith(b"\n"):
                chunk = conn.recv(256)
                if not chunk:
                    break
                received += chunk
            exchange["received"] = received
            if received == b"STATUS: READY_TO_RESTORE\n":
                conn.sendall(b"CMD: PROCEED\n")

    thread = threading.Thread(target=health_service, daemon=True)
    thread.start()

    try:
        with tempfile.TemporaryDirectory(prefix="verified_restore_") as output_dir:
            env = os.environ.copy()
            env["RESTORE_MASTER_KEY"] = "drill_token_8891"
            proc = subprocess.run(
                [RESTORE_AGENT, BACKUP_PATH, output_dir],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                check=False,
            )
            thread.join(timeout=6)

            assert exchange.get("received") == b"STATUS: READY_TO_RESTORE\n", \
                "Restore agent did not perform the required health protocol"
            assert proc.returncode == 0, \
                f"Restore agent failed: {proc.stderr.decode(errors='replace')}"
            assert b"Restore successful" in proc.stdout, \
                "Restore agent did not report a successful restore"

            expected_paths = {
                "manifest.json": os.path.join(output_dir, "manifest.json"),
                "data.csv": os.path.join(output_dir, "data.csv"),
            }
            for name, path in expected_paths.items():
                assert os.path.isfile(path), f"Restore agent did not produce {name}"

            expected = {}
            for name, path in expected_paths.items():
                with open(path, "rb") as f:
                    expected[name] = f.read()
            yield expected
    finally:
        listener.close()


def test_log_file_exists():
    assert os.path.exists(LOG_PATH), f"Log file missing: {LOG_PATH}"
    assert os.path.isfile(LOG_PATH), f"Log path is not a file: {LOG_PATH}"
    assert os.path.getsize(LOG_PATH) > 0, "Health daemon log is empty"


def test_restored_files_exist_and_match_restore_agent(oracle_restore):
    assert os.path.exists(MANIFEST_PATH), f"Restored manifest missing: {MANIFEST_PATH}"
    assert os.path.exists(DATA_CSV_PATH), f"Restored data missing: {DATA_CSV_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"Manifest is not a regular file: {MANIFEST_PATH}"
    assert os.path.isfile(DATA_CSV_PATH), f"Data is not a regular file: {DATA_CSV_PATH}"

    with open(MANIFEST_PATH, "rb") as f:
        assert f.read() == oracle_restore["manifest.json"], \
            "manifest.json does not match the restore agent's output"
    with open(DATA_CSV_PATH, "rb") as f:
        assert f.read() == oracle_restore["data.csv"], \
            "data.csv does not match the restore agent's output"


def test_http_server_auth_and_content(oracle_restore):
    manifest_content = oracle_restore["manifest.json"]
    data_content = oracle_restore["data.csv"]
    password = hashlib.md5(manifest_content).hexdigest()
    username = "backup_admin"

    try:
        resp_no_auth = requests.get(f"{SERVER_URL}/manifest.json", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {SERVER_URL}: {e}")

    assert resp_no_auth.status_code == 401, \
        "Server did not require authentication (expected 401 Unauthorized)"

    resp_bad_auth = requests.get(
        f"{SERVER_URL}/manifest.json",
        auth=(username, "wrongpassword"),
        timeout=5,
    )
    assert resp_bad_auth.status_code == 401, "Server accepted invalid credentials"

    resp_auth = requests.get(
        f"{SERVER_URL}/manifest.json",
        auth=(username, password),
        timeout=5,
    )
    assert resp_auth.status_code == 200, \
        f"Server rejected valid credentials, got status {resp_auth.status_code}"
    assert resp_auth.content == manifest_content, \
        "Served manifest.json content does not match the verified restore output"

    resp_data = requests.get(
        f"{SERVER_URL}/data.csv",
        auth=(username, password),
        timeout=5,
    )
    assert resp_data.status_code == 200, \
        f"Failed to fetch data.csv, got status {resp_data.status_code}"
    assert resp_data.content == data_content, \
        "Served data.csv content does not match the verified restore output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
