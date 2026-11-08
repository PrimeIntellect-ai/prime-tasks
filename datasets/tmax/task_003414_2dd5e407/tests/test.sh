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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid

import pytest
import requests

PROJECT = "/home/user/artifact_manager"
CHUNKS = "/home/user/data/chunks"
ACTIVE = "/home/user/data/active"
ARCHIVES = "/home/user/data/archives"
SYNC_LOG = "/home/user/data/sync.log"
_runtime = None


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def rust_runtime():
    global _runtime
    if _runtime is not None:
        return _runtime

    pids = listener_pids(9000)
    assert pids, "No process is listening on the required Rust backend port 9000"
    selected = None
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
        except OSError:
            continue
        if exe.startswith(PROJECT + os.sep) and os.path.isfile(exe):
            selected = (pid, exe, cwd)
            break
    assert selected is not None, "The port 9000 server is not an executable built inside the Rust project"
    _runtime = selected
    return selected


def exact_chunks(filename, original):
    expected_count = (len(original) + 511999) // 512000
    expected_names = [f"{filename}.chunk.{i:03d}" for i in range(1, expected_count + 1)]
    actual_names = sorted(
        name for name in os.listdir(CHUNKS)
        if name.startswith(filename + ".chunk.")
    )
    assert actual_names == expected_names, f"Wrong chunk set for {filename}: {actual_names}"

    rebuilt = bytearray()
    for index, name in enumerate(actual_names):
        path = os.path.join(CHUNKS, name)
        assert os.path.isfile(path) and not os.path.islink(path), f"{name} is not a regular chunk file"
        with open(path, "rb") as f:
            body = f.read()
        if index < len(actual_names) - 1:
            assert len(body) == 512000, f"Chunk {name} has incorrect size: {len(body)}"
        else:
            assert 0 < len(body) <= 512000, f"Last chunk {name} has incorrect size: {len(body)}"
        rebuilt.extend(body)
    assert bytes(rebuilt) == original, f"Chunks for {filename} do not reconstruct the archive"


def test_rust_project_and_running_backend():
    assert os.path.isdir(PROJECT), "Rust project directory is missing"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    source_files = []
    for root, _, files in os.walk(os.path.join(PROJECT, "src")):
        source_files.extend(os.path.join(root, f) for f in files if f.endswith(".rs"))
    assert source_files, "The project contains no Rust source files"

    pid, exe, _ = rust_runtime()
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The backend executable is not an ELF binary"

    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert metadata.returncode == 0, f"Invalid Cargo project: {metadata.stderr}"
    data = json.loads(metadata.stdout)
    bin_names = {
        target["name"]
        for package in data["packages"]
        for target in package["targets"]
        if "bin" in target["kind"]
    }
    assert bin_names, "Cargo project has no binary target"
    normalized_exe = os.path.realpath(exe)
    assert any(
        normalized_exe.endswith(f"/target/debug/{name}") or
        normalized_exe.endswith(f"/target/release/{name}")
        for name in bin_names
    ), "The port 9000 process is not one of this Cargo project's binary targets"

    built = subprocess.run(
        ["cargo", "build", "--offline"], cwd=PROJECT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert built.returncode == 0, f"Rust project does not build successfully: {built.stderr}"

    finished = "/home/user/finished.txt"
    assert os.path.isfile(finished), "Completion log /home/user/finished.txt is missing"
    assert os.path.getsize(finished) > 0, "Completion log is empty"


def test_chunks_created_correctly():
    """Verify exact chunks are created for the valid fixture and not the corrupt one."""
    with open(os.path.join(ARCHIVES, "app-v1.tar.gz"), "rb") as f:
        original = f.read()
    exact_chunks("app-v1.tar.gz", original)

    corrupt_chunks = [f for f in os.listdir(CHUNKS) if f.startswith("corrupt-v2.tar.gz")]
    assert len(corrupt_chunks) == 0, "Chunks found for corrupt-v2.tar.gz, but it should have been skipped."


def test_symlinks_created_correctly():
    app_symlink = os.path.join(ACTIVE, "app-v1.tar.gz")
    corrupt_symlink = os.path.join(ACTIVE, "corrupt-v2.tar.gz")
    assert os.path.islink(app_symlink), "Symlink for app-v1.tar.gz is missing."
    target = os.readlink(app_symlink)
    assert target == "/home/user/data/archives/app-v1.tar.gz", f"Symlink points to wrong target: {target}"
    assert not os.path.exists(corrupt_symlink) and not os.path.islink(corrupt_symlink), "Symlink found for corrupt-v2.tar.gz."


def test_processor_on_derived_inputs_and_restart_backend():
    """Restart the submitted Rust binary with unpredictable valid and invalid records."""
    global _runtime
    token = uuid.uuid4().hex
    valid_name = f"audit-{token}.tar.gz"
    corrupt_name = f"audit-corrupt-{token}.tar.gz"
    valid_path = os.path.join(ARCHIVES, valid_name)
    corrupt_path = os.path.join(ARCHIVES, corrupt_name)

    payload_path = os.path.join("/tmp", f"payload-{token}")
    with open(payload_path, "wb") as f:
        f.write(os.urandom(700000))
    with tarfile.open(valid_path, "w:gz") as tf:
        tf.add(payload_path, arcname="payload.bin")
    os.unlink(payload_path)
    with open(corrupt_path, "wb") as f:
        f.write(os.urandom(4097))

    with open(valid_path, "rb") as f:
        valid_body = f.read()
    with open(SYNC_LOG, "a") as f:
        f.write(
            f"\n[START UPLOAD]\nFile: {valid_name}\nExpected-Size: {len(valid_body)}\n[END UPLOAD]\n"
            f"[START UPLOAD]\nFile: {corrupt_name}\nExpected-Size: {os.path.getsize(corrupt_path)}\n[END UPLOAD]\n"
        )

    pid, exe, cwd = rust_runtime()
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and os.path.exists(f"/proc/{pid}"):
        time.sleep(0.05)
    if os.path.exists(f"/proc/{pid}"):
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.2)

    proc = subprocess.Popen([exe], cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _runtime = (proc.pid, exe, cwd)
    wait_for_port(9000)

    deadline = time.time() + 15
    while time.time() < deadline:
        if os.path.islink(os.path.join(ACTIVE, valid_name)):
            break
        time.sleep(0.1)

    exact_chunks(valid_name, valid_body)
    link = os.path.join(ACTIVE, valid_name)
    assert os.path.islink(link), "Derived valid archive did not receive a symlink"
    assert os.readlink(link) == valid_path, "Derived valid archive symlink has the wrong target"
    assert not any(name.startswith(corrupt_name) for name in os.listdir(CHUNKS)), "Derived corrupt archive was chunked"
    bad_link = os.path.join(ACTIVE, corrupt_name)
    assert not os.path.exists(bad_link) and not os.path.islink(bad_link), "Derived corrupt archive was activated"

    direct = requests.get("http://127.0.0.1:9000/health", timeout=5)
    assert direct.status_code == 200
    assert direct.text.strip() == "System Operational"

    downloaded = requests.get(f"http://127.0.0.1:8080/downloads/{valid_name}", timeout=5)
    assert downloaded.status_code == 200
    assert downloaded.content == valid_body


def test_nginx_is_listener():
    pids = listener_pids(8080)
    assert pids, "Nothing is listening on port 8080"
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert any(os.path.basename(exe) == "nginx" for exe in executables), "Port 8080 is not served by Nginx"


def test_api_health():
    url = "http://127.0.0.1:8080/api/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.text.strip() == "System Operational", f"Expected body 'System Operational', got '{response.text}'"


def test_downloads_valid_archive():
    url = "http://127.0.0.1:8080/downloads/app-v1.tar.gz"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    with open(os.path.join(ARCHIVES, "app-v1.tar.gz"), "rb") as f:
        expected_content = f.read()
    assert response.content == expected_content, "Downloaded content does not match the original archive."


def test_downloads_corrupt_archive():
    url = "http://127.0.0.1:8080/downloads/corrupt-v2.tar.gz"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 404, f"Expected status 404 for missing file, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
