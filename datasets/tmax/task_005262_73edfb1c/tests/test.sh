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
mkdir -p /logs/verifier
reward=0

if (
set -e

ROOT=/app/artifact_manager
BACKEND="$ROOT/rust_backend/target/debug/artifact_backend"
TEST_NAME="verifier_$(python3 -c 'import secrets; print(secrets.token_hex(12))').bin"
MISSING_NAME="missing_$(python3 -c 'import secrets; print(secrets.token_hex(12))').bin"
TEST_FILE="$ROOT/data/binaries/$TEST_NAME"
BACKEND_PID=""
NGINX_LAUNCHER_PID=""

kill_listeners() {
    python3 - "$@" <<'PY'
import os
import signal
import sys
import time

ports = {int(value) for value in sys.argv[1:]}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) >= 10 and fields[3] == "0A":
            port = int(fields[1].rsplit(":", 1)[1], 16)
            if port in ports:
                inodes.add(fields[9])

victims = set()
for entry in os.listdir("/proc"):
    if not entry.isdigit():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(entry))
                break
    except OSError:
        pass

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.5)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

cleanup() {
    rm -f "$TEST_FILE"
    if [ -n "$BACKEND_PID" ]; then kill "$BACKEND_PID" 2>/dev/null || true; fi
    if [ -n "$NGINX_LAUNCHER_PID" ]; then kill "$NGINX_LAUNCHER_PID" 2>/dev/null || true; fi
    kill_listeners 8000 9000 >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Inspect and compile the submitted Rust implementation.
test -f "$ROOT/rust_backend/src/main.rs"
python3 - <<'PY'
import pathlib
import re

src_dir = pathlib.Path("/app/artifact_manager/rust_backend/src")
files = list(src_dir.rglob("*.rs"))
assert files, "No Rust source files were found"
source = "\n".join(path.read_text(encoding="utf-8") for path in files)
# Ignore comments so merely mentioning mmap in a TODO/comment is insufficient.
source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
source = re.sub(r"//.*", "", source)
assert re.search(r"\bmemmap2\b", source), "Rust source does not use the memmap2 crate"
assert re.search(r"(?:::|\.)map\s*\(", source), "Rust source does not perform a memory-map operation"
PY
(
    cd "$ROOT/rust_backend"
    cargo build
)
test -x "$BACKEND"

# Add an unpredictable artifact so a server hard-coded for the shipped sample cannot pass.
python3 - "$TEST_FILE" <<'PY'
import os
import sys
with open(sys.argv[1], "wb") as f:
    f.write(os.urandom(131071))
PY

# Replace any pre-existing/fake listeners, then run the freshly compiled backend
# and the submitted Nginx configuration.
kill_listeners 8000 9000
"$BACKEND" >/tmp/verifier-backend.log 2>&1 &
BACKEND_PID=$!

python3 - <<'PY'
import requests
import time
url = "http://127.0.0.1:9000/artifact/__verifier_startup_probe__"
last = None
for _ in range(50):
    try:
        last = requests.get(url, timeout=0.3)
        if last.status_code == 404:
            break
    except requests.RequestException:
        pass
    time.sleep(0.1)
else:
    raise AssertionError(f"Freshly built Rust backend did not start on 127.0.0.1:9000; last response={last!r}")
PY

nginx -t -c "$ROOT/nginx/nginx.conf"
nginx -c "$ROOT/nginx/nginx.conf" >/tmp/verifier-nginx.log 2>&1 &
NGINX_LAUNCHER_PID=$!

python3 - <<'PY'
import requests
import time
url = "http://127.0.0.1:8000/api/artifact/__verifier_startup_probe__"
last = None
for _ in range(50):
    try:
        last = requests.get(url, timeout=0.3)
        if last.status_code == 404:
            break
    except requests.RequestException:
        pass
    time.sleep(0.1)
else:
    raise AssertionError(f"Nginx did not start/proxy on 127.0.0.1:8000; last response={last!r}")
PY

export VERIFIER_TEST_NAME="$TEST_NAME"
export VERIFIER_MISSING_NAME="$MISSING_NAME"
cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import requests
import pytest

ROOT = "/app/artifact_manager"


def listening_socket_owners(port):
    inodes = set()
    addresses = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                host_hex, port_hex = fields[1].rsplit(":", 1)
                if int(port_hex, 16) == port:
                    inodes.add(fields[9])
                    addresses.add((table, host_hex))

    owners = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            links = [os.readlink(f"{fd_dir}/{fd}") for fd in os.listdir(fd_dir)]
        except OSError:
            continue
        if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            try:
                owners.append(os.path.realpath(f"/proc/{entry}/exe"))
            except OSError:
                pass
    return addresses, owners


def assert_download(url, expected):
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert resp.status_code == 200, f"Expected HTTP status 200, got {resp.status_code}. Response: {resp.text[:100]}"
    content_type = resp.headers.get("Content-Type", "")
    assert "application/octet-stream" in content_type, f"Expected Content-Type application/octet-stream, got {content_type!r}"
    assert resp.content == expected, "The downloaded content does not match the local binary file."


def test_csv_conversion():
    legacy_path = f"{ROOT}/data/manifest.legacy"
    csv_path = f"{ROOT}/data/manifest.csv"
    assert os.path.exists(csv_path), f"{csv_path} does not exist. Did you create the CSV file?"
    with open(legacy_path, "r", encoding="iso-8859-1") as f:
        legacy_lines = [line.strip() for line in f if line.strip()]
    expected_rows = ["File,Hash,Bytes"] + [line.replace("|", ",") for line in legacy_lines]
    try:
        with open(csv_path, "r", encoding="utf-8") as f:
            csv_lines = [line.strip() for line in f if line.strip()]
    except UnicodeDecodeError:
        pytest.fail(f"{csv_path} is not valid UTF-8 encoded.")
    assert csv_lines == expected_rows, "CSV content does not match the expected transformation from the legacy file."


def test_required_services_own_loopback_ports():
    addresses9000, owners9000 = listening_socket_owners(9000)
    addresses8000, owners8000 = listening_socket_owners(8000)
    assert ("/proc/net/tcp", "0100007F") in addresses9000, "Backend is not listening on 127.0.0.1:9000"
    assert ("/proc/net/tcp", "0100007F") in addresses8000, "Nginx is not listening on 127.0.0.1:8000"
    expected_backend = os.path.realpath(f"{ROOT}/rust_backend/target/debug/artifact_backend")
    assert expected_backend in owners9000, f"Port 9000 is not owned by the freshly compiled Rust backend: {owners9000}"
    assert any(path.endswith("/nginx") for path in owners8000), f"Port 8000 is not owned by Nginx: {owners8000}"


def test_http_artifact_download():
    binary_path = f"{ROOT}/data/binaries/test_artifact.bin"
    assert os.path.exists(binary_path), f"Truth binary {binary_path} is missing."
    expected = pathlib.Path(binary_path).read_bytes()
    assert_download("http://127.0.0.1:8000/api/artifact/test_artifact.bin", expected)


def test_dynamic_artifact_through_backend_and_nginx():
    name = os.environ["VERIFIER_TEST_NAME"]
    expected = pathlib.Path(f"{ROOT}/data/binaries/{name}").read_bytes()
    assert_download(f"http://127.0.0.1:9000/artifact/{name}", expected)
    assert_download(f"http://127.0.0.1:8000/api/artifact/{name}", expected)


def test_http_artifact_not_found():
    urls = [
        "http://127.0.0.1:8000/api/artifact/nonexistent_file_12345.bin",
        f"http://127.0.0.1:9000/artifact/{os.environ['VERIFIER_MISSING_NAME']}",
        f"http://127.0.0.1:8000/api/artifact/{os.environ['VERIFIER_MISSING_NAME']}",
    ]
    for url in urls:
        try:
            resp = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")
        assert resp.status_code == 404, f"Expected HTTP status 404 for {url}, got {resp.status_code}. Response: {resp.text[:100]}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
) then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
