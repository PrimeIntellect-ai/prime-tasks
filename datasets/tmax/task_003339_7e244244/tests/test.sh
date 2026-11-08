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
import glob
import json
import os
import random
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH = {"Authorization": "Bearer project-alpha-99"}
SERVER_PROCESS = None


def listener_pids(port):
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
                    if local.rsplit(":", 1)[1].upper() == wanted and state == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    found = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                found.add(pid)
                break
    return found


def build_and_start_submitted_rust_server():
    global SERVER_PROCESS
    project = "/home/user/log_api"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isfile(manifest), "The Rust API project is missing Cargo.toml"
    assert glob.glob(os.path.join(project, "**", "*.rs"), recursive=True), "No Rust source files were found"

    for pid in listener_pids(8080):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 5
    while listener_pids(8080) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)

    built = subprocess.run(
        ["cargo", "build", "--offline"], cwd=project,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300
    )
    assert built.returncode == 0, "Submitted Rust project did not build:\n" + built.stdout[-4000:]

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1"],
        cwd=project, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert metadata_run.returncode == 0, "Could not inspect submitted Cargo project: " + metadata_run.stderr
    metadata = json.loads(metadata_run.stdout)

    manifest_real = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    if not packages:
        workspace_members = set(metadata.get("workspace_members", []))
        packages = [p for p in metadata["packages"] if p["id"] in workspace_members]
    assert packages, "Cargo project has no workspace package"

    candidates = []
    for package in packages:
        bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
        default = package.get("default_run")
        if default:
            bins.sort(key=lambda t: t["name"] != default)
        candidates.extend(bins)
    assert candidates, "Cargo project does not define a Rust binary target"

    target_dir = metadata["target_directory"]
    binary = os.path.join(target_dir, "debug", candidates[0]["name"])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), f"Built Rust server binary not found at {binary}"

    SERVER_PROCESS = subprocess.Popen(
        [binary], cwd=project, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            pytest.fail(f"Built Rust server exited with code {SERVER_PROCESS.returncode}")
        try:
            requests.get(BASE_URL + "/download?date=1900-01-01", timeout=0.3)
            return
        except requests.RequestException:
            time.sleep(0.15)
    pytest.fail("The built Rust server did not listen on 127.0.0.1:8080")


build_and_start_submitted_rust_server()


def test_clean_logs_app1():
    path = "/home/user/clean_logs/2023-10-25/app1.log"
    assert os.path.isfile(path), f"File {path} not found. The log file was not correctly processed and moved."
    with open(path, "r") as f:
        content = f.read()
    assert "[2023-10-25 10:15:30]" in content, "Timestamps in app1.log were not correctly standardized to YYYY-MM-DD."
    assert "END_OF_TRANSACTION" in content, "END_OF_TRANSACTION missing from app1.log."


def test_clean_logs_app2():
    path = "/home/user/clean_logs/2023-10-26/app2.log"
    assert os.path.isfile(path), f"File {path} not found. The compliant log file was not correctly moved."
    with open(path, "r") as f:
        content = f.read()
    assert "[2023-10-26 11:00:00]" in content, "Timestamps in app2.log were altered incorrectly."


def test_clean_logs_app3():
    path = "/home/user/clean_logs/2023-10-27/app3.log"
    assert not os.path.isfile(path), f"File {path} should have been discarded because it was not compliant."


def test_recursive_cleanup_and_preserved_multiline_content():
    remaining = glob.glob("/home/user/raw_logs/**/*.log", recursive=True)
    assert not remaining, f"Log files were left behind instead of being recursively processed: {remaining}"
    with open("/home/user/clean_logs/2023-10-25/app1.log") as f:
        assert f.read() == (
            "[2023-10-25 10:15:30] ERROR Database connection failed\n"
            "  at line 45\n"
            "  at main module\n"
            "[2023-10-25 10:16:00] INFO Retrying...\n"
            "END_OF_TRANSACTION\n"
        ), "Timestamp conversion damaged entries or their multiline stack trace"
    assert not glob.glob("/home/user/clean_logs/**/app3.log", recursive=True), "Invalid app3.log was not discarded"


def test_api_unauthorized():
    try:
        resp = requests.get("http://127.0.0.1:8080/download?date=2023-10-25")
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Rust API at 127.0.0.1:8080")

    assert resp.status_code == 401, f"Expected 401 Unauthorized without Auth header, got {resp.status_code}"


def test_api_download_authorized():
    headers = {"Authorization": "Bearer project-alpha-99"}
    try:
        resp = requests.get("http://127.0.0.1:8080/download?date=2023-10-25", headers=headers)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Rust API at 127.0.0.1:8080")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    assert "gzip" in resp.headers.get("Content-Type", ""), f"Expected application/gzip content type, got {resp.headers.get('Content-Type')}"

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(resp.content)
        tmp_path = tmp.name

    try:
        with tarfile.open(tmp_path, "r:gz") as tar:
            names = tar.getnames()
            assert any("app1.log" in name for name in names), f"app1.log not found in the downloaded archive. Found: {names}"
    except tarfile.ReadError:
        pytest.fail("The downloaded file is not a valid gzip tar archive.")
    finally:
        os.remove(tmp_path)


def test_api_verify():
    headers = {"Authorization": "Bearer project-alpha-99"}
    payload = {"path": "/home/user/clean_logs/2023-10-26/app2.log"}
    try:
        resp = requests.post("http://127.0.0.1:8080/verify", headers=headers, json=payload)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Rust API at 127.0.0.1:8080")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Expected JSON response from /verify endpoint.")

    assert data.get("status") == "compliant", f"Expected status 'compliant', got {data.get('status')}"


def test_all_defined_routes_require_authorization():
    bad = {"Authorization": "Bearer wrong-token"}
    for headers in ({}, bad):
        download = requests.get(BASE_URL + "/download?date=2023-10-25", headers=headers, timeout=5)
        verify = requests.post(BASE_URL + "/verify", headers=headers, json={"path": "/tmp/no-file"}, timeout=5)
        assert download.status_code == 401, f"/download accepted unauthorized headers {headers}"
        assert verify.status_code == 401, f"/verify accepted unauthorized headers {headers}"


def test_dynamic_download_and_missing_date():
    while True:
        date = f"{random.randint(2040, 2090):04d}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
        directory = os.path.join("/home/user/clean_logs", date)
        if not os.path.exists(directory):
            break
    os.makedirs(directory)
    filename = "runtime-" + os.urandom(8).hex() + ".log"
    payload = os.urandom(257)
    with open(os.path.join(directory, filename), "wb") as f:
        f.write(payload)
    try:
        response = requests.get(BASE_URL + "/download", params={"date": date}, headers=AUTH, timeout=10)
        assert response.status_code == 200, f"Dynamic date download returned {response.status_code}"
        assert "gzip" in response.headers.get("Content-Type", "").lower()
        with tempfile.NamedTemporaryFile() as archive:
            archive.write(response.content)
            archive.flush()
            with tarfile.open(archive.name, "r:gz") as tf:
                members = [m for m in tf.getmembers() if m.isfile() and os.path.basename(m.name) == filename]
                assert len(members) == 1, f"Runtime-created file was absent from archive: {tf.getnames()}"
                extracted = tf.extractfile(members[0])
                assert extracted is not None and extracted.read() == payload, "Archive did not contain current on-disk bytes"
    finally:
        shutil.rmtree(directory, ignore_errors=True)

    while True:
        missing = f"{random.randint(2100, 2190):04d}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
        if not os.path.exists(os.path.join("/home/user/clean_logs", missing)):
            break
    response = requests.get(BASE_URL + "/download", params={"date": missing}, headers=AUTH, timeout=5)
    assert response.status_code == 404, f"Missing date should return 404, got {response.status_code}"


def test_verify_executes_legacy_oracle_for_arbitrary_files():
    work = tempfile.mkdtemp(prefix="api-oracle-test-")
    valid = os.path.join(work, "valid-" + os.urandom(6).hex() + ".log")
    invalid = os.path.join(work, "invalid-" + os.urandom(6).hex() + ".log")
    with open(valid, "w") as f:
        f.write(f"[2061-04-03 02:01:00] nonce {os.urandom(10).hex()}\nEND_OF_TRANSACTION\n")
    with open(invalid, "w") as f:
        f.write(f"[03-04-2061 02:01:00] nonce {os.urandom(10).hex()}\n")

    oracle = "/app/legacy_verifier"
    expected = {
        valid: "compliant" if subprocess.run([oracle, valid]).returncode == 0 else "invalid",
        invalid: "compliant" if subprocess.run([oracle, invalid]).returncode == 0 else "invalid",
    }
    assert set(expected.values()) == {"compliant", "invalid"}, "Challenge inputs did not exercise both oracle outcomes"

    original = os.path.join(work, "legacy_verifier.original")
    marker = os.path.join(work, "invocations")
    os.replace(oracle, original)
    try:
        with open(oracle, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + json.dumps(marker) + "\nexec " + json.dumps(original) + " \"$@\"\n")
        os.chmod(oracle, 0o755)

        for path in (valid, invalid):
            response = requests.post(BASE_URL + "/verify", headers=AUTH, json={"path": path}, timeout=10)
            assert response.status_code == 200, f"/verify returned {response.status_code}: {response.text}"
            assert response.headers.get("Content-Type", "").lower().startswith("application/json")
            assert response.json().get("status") == expected[path], "API result disagreed with the legacy verifier"

        assert os.path.isfile(marker), "/verify did not execute /app/legacy_verifier"
        with open(marker) as f:
            invoked = f.read().splitlines()
        assert valid in invoked and invalid in invoked, "/verify did not pass each requested path to /app/legacy_verifier"
    finally:
        try:
            os.remove(oracle)
        except FileNotFoundError:
            pass
        if os.path.exists(original):
            os.replace(original, oracle)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
