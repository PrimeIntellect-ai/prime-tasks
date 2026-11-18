#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import gzip
import time
import socket
import fcntl
import threading
import uuid
import requests
import pytest
from concurrent.futures import ThreadPoolExecutor

PORT = 8118
HOST = "127.0.0.1"
API_TOKEN = "AlphaBravoCharlie99"
ACTIVE_CONFIGS_DIR = "/home/user/active_configs"
CHANGELOG_FILE = "/home/user/system_changelog.log"
LEGACY_CONFIGS_DIR = "/app/legacy_configs"


def wait_for_service():
    """Wait for the service to be reachable."""
    max_retries = 30
    for _ in range(max_retries):
        try:
            with socket.create_connection((HOST, PORT), timeout=1):
                return True
        except (socket.timeout, socket.error):
            time.sleep(1)
    return False


@pytest.fixture(scope="module", autouse=True)
def setup_service():
    assert wait_for_service(), f"Service is not listening on {HOST}:{PORT}"


def test_legacy_migration():
    """Verify that legacy configs were correctly migrated and renamed."""
    expected_files = [
        "auth_svc_v2.json.gz",
        "payment_gw_v1.json.gz"
    ]
    for filename in expected_files:
        filepath = os.path.join(ACTIVE_CONFIGS_DIR, filename)
        assert os.path.isfile(filepath), f"Legacy config not found at {filepath}"

        try:
            with gzip.open(filepath, 'rt') as f:
                data = json.load(f)
                assert "service_name" in data
                assert "version" in data
        except Exception as e:
            pytest.fail(f"Failed to read {filepath} as gzipped JSON: {e}")


def test_every_legacy_file_was_copied_using_its_metadata():
    sources = sorted(
        os.path.join(LEGACY_CONFIGS_DIR, name)
        for name in os.listdir(LEGACY_CONFIGS_DIR)
        if name.endswith(".gz")
    )
    assert sources, "No legacy gzip files found"

    for source in sources:
        with gzip.open(source, "rt") as f:
            data = json.load(f)
        assert isinstance(data.get("service_name"), str)
        assert "version" in data
        expected_name = f"{data['service_name']}_v{data['version']}.json.gz"
        destination = os.path.join(ACTIVE_CONFIGS_DIR, expected_name)
        assert os.path.isfile(destination), f"Missing migration output for {source}: {destination}"

        with open(source, "rb") as src, open(destination, "rb") as dst:
            assert dst.read() == src.read(), f"{destination} is not a copy of {source}"

        with gzip.open(destination, "rt") as f:
            migrated = json.load(f)
        assert migrated == data
        assert expected_name == f"{migrated['service_name']}_v{migrated['version']}.json.gz"


def test_unauthorized_request():
    """Verify that requests without the correct token are rejected."""
    url = f"http://{HOST}:{PORT}/upload"
    payload = {"service_name": "test_unauth", "version": 1, "settings": {}}
    gzipped_payload = gzip.compress(json.dumps(payload).encode('utf-8'))

    response = requests.post(url, data=gzipped_payload)
    assert response.status_code == 401, "Expected 401 Unauthorized for missing token"

    headers = {"Authorization": "Bearer WrongToken123"}
    response = requests.post(url, data=gzipped_payload, headers=headers)
    assert response.status_code == 401, "Expected 401 Unauthorized for incorrect token"


def test_upload_and_concurrency():
    """Verify that concurrent uploads work and changelog is locked correctly."""
    url = f"http://{HOST}:{PORT}/upload"
    headers = {"Authorization": f"Bearer {API_TOKEN}"}

    def upload_config(i):
        service_name = f"concurrent_svc_{i}"
        version = i
        payload = {"service_name": service_name, "version": version, "settings": {"index": i}}
        gzipped_payload = gzip.compress(json.dumps(payload).encode('utf-8'))

        response = requests.post(url, data=gzipped_payload, headers=headers)
        return response.status_code, service_name, version

    num_requests = 10
    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(upload_config, range(num_requests)))

    for status, svc, ver in results:
        assert status == 200, f"Expected 200 OK for {svc}, got {status}"

        filepath = os.path.join(ACTIVE_CONFIGS_DIR, f"{svc}_v{ver}.json.gz")
        assert os.path.isfile(filepath), f"Uploaded config not found at {filepath}"

        with gzip.open(filepath, 'rt') as f:
            data = json.load(f)
            assert data["service_name"] == svc
            assert data["version"] == ver

    assert os.path.isfile(CHANGELOG_FILE), f"Changelog file missing at {CHANGELOG_FILE}"
    with open(CHANGELOG_FILE, 'r') as f:
        lines = f.readlines()

    for line in lines:
        assert line.startswith("UPDATED ") and " TO v" in line and line.endswith("\n"), f"Malformed changelog line: {repr(line)}"

    for _, svc, ver in results:
        expected_log = f"UPDATED {svc} TO v{ver}\n"
        assert expected_log in lines, f"Missing log entry for {svc} in changelog"


def test_upload_uses_os_level_exclusive_changelog_lock():
    """Hold kernel locks and prove the daemon queues for one before appending."""
    url = f"http://{HOST}:{PORT}/upload"
    headers = {"Authorization": f"Bearer {API_TOKEN}"}
    unique = uuid.uuid4().hex
    service_name = f"lock_probe_{unique}"
    version = 73001
    payload = {
        "service_name": service_name,
        "version": version,
        "settings": {"nonce": unique, "nested": [1, 2, 3]},
    }
    body = gzip.compress(json.dumps(payload).encode("utf-8"))

    # Ensure the file and its current inode exist before taking the locks.
    os.makedirs(os.path.dirname(CHANGELOG_FILE), exist_ok=True)
    with open(CHANGELOG_FILE, "a+b") as lock_file:
        # flock covers fs3/flock implementations; lockf covers POSIX fcntl locks.
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)
        inode = os.fstat(lock_file.fileno()).st_ino
        started = threading.Event()

        def send_request():
            started.set()
            return requests.post(url, data=body, headers=headers, timeout=15)

        executor = ThreadPoolExecutor(max_workers=1)
        future = executor.submit(send_request)
        assert started.wait(2), "Lock probe request did not start"

        kernel_waiter_seen = False
        deadline = time.time() + 3
        while time.time() < deadline and not future.done():
            try:
                with open("/proc/locks", "r") as proc_locks:
                    for line in proc_locks:
                        if "->" in line and ("FLOCK" in line or "POSIX" in line or "OFDLCK" in line):
                            fields = line.split()
                            if any(field.endswith(f":{inode}") for field in fields):
                                kernel_waiter_seen = True
                                break
            except OSError:
                pass
            if kernel_waiter_seen:
                break
            time.sleep(0.05)

        blocked = not future.done()
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

        try:
            response = future.result(timeout=10)
        finally:
            executor.shutdown(wait=False)

    assert blocked, "Upload completed while another process held the changelog lock"
    assert kernel_waiter_seen, "Daemon did not request an OS-level lock on the changelog"
    assert response.status_code == 200

    destination = os.path.join(ACTIVE_CONFIGS_DIR, f"{service_name}_v{version}.json.gz")
    assert os.path.isfile(destination)
    with gzip.open(destination, "rt") as f:
        assert json.load(f) == payload
    with open(CHANGELOG_FILE, "r") as f:
        assert f"UPDATED {service_name} TO v{version}\n" in f.readlines()
TEST_EOF

PROJECT=/home/user/config_daemon
if [ -f "$PROJECT/Cargo.toml" ] && find "$PROJECT" -type f -name '*.rs' -print -quit | grep -q .; then
    cd "$PROJECT"
    if timeout 180 cargo build --bins --message-format=json > /tmp/config_daemon_build.json 2>/tmp/config_daemon_build.err; then
        BIN=$(python3 - << 'PY'
import json
found = []
with open('/tmp/config_daemon_build.json', 'r') as f:
    for line in f:
        try:
            item = json.loads(line)
        except Exception:
            continue
        if item.get('reason') == 'compiler-artifact' and 'bin' in item.get('target', {}).get('kind', []):
            executable = item.get('executable')
            if executable:
                found.append(executable)
print(found[-1] if found else '')
PY
)
        if [ -n "$BIN" ] && [ -x "$BIN" ]; then
            python3 - << 'PY'
import os, signal, time
port_hex = format(8118, '04X')
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].split(':')[-1].upper() == port_hex and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass
for pid in pids:
    try: os.kill(pid, signal.SIGTERM)
    except OSError: pass
time.sleep(1)
for pid in pids:
    try: os.kill(pid, signal.SIGKILL)
    except OSError: pass
PY
            cd "$PROJECT"
            nohup "$BIN" >/tmp/config_daemon_verifier.log 2>&1 &
            if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
                reward=1
            fi
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
