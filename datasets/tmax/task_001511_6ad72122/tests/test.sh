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
import signal
import subprocess
import time
import uuid

import pytest
import requests

AUTH_KEY = "KEY_B5x9_P!q2M"
SERVER_URL = "http://127.0.0.1:8080/manifest"
CONFIG_DIR = "/home/user/extracted_configs"
SOURCE = "/home/user/config_server.c"
BINARY = "/home/user/config_server"


def get_expected_manifest():
    app1_content = b"server_ip=10.0.0.50\nmode=modern\nthreads=4\n"
    db_content = b"server_ip=10.0.0.101\nmode=modern\ncache=256M\n"
    app1_sha = hashlib.sha256(app1_content).hexdigest()
    db_sha = hashlib.sha256(db_content).hexdigest()
    return f"app1.conf:{app1_sha}\ndb.conf:{db_sha}"


def manifest_from_disk():
    lines = []
    for name in sorted(os.listdir(CONFIG_DIR)):
        path = os.path.join(CONFIG_DIR, name)
        if name.endswith(".conf") and os.path.isfile(path):
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            lines.append(f"{name}:{digest}")
    return "\n".join(lines)


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def kill_port_8080():
    inodes = listener_inodes()
    if not inodes:
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(entry), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)


def start_server(executable):
    kill_port_8080()
    proc = subprocess.Popen([executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 4
    while time.time() < deadline:
        try:
            requests.get(SERVER_URL, timeout=0.25)
            return proc
        except requests.exceptions.RequestException:
            time.sleep(0.05)
    if proc.poll() is None:
        proc.terminate()
    pytest.fail(f"Server executable {executable!r} did not begin listening on 127.0.0.1:8080")


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)
    kill_port_8080()


def test_extracted_configs_exist_and_modified():
    app1_path = os.path.join(CONFIG_DIR, "app1.conf")
    db_path = os.path.join(CONFIG_DIR, "db.conf")
    assert os.path.isfile(app1_path), f"Expected config file '{app1_path}' is missing."
    assert os.path.isfile(db_path), f"Expected config file '{db_path}' is missing."
    with open(app1_path, "rb") as f:
        app1_content = f.read()
    with open(db_path, "rb") as f:
        db_content = f.read()
    expected_app1 = b"server_ip=10.0.0.50\nmode=modern\nthreads=4\n"
    expected_db = b"server_ip=10.0.0.101\nmode=modern\ncache=256M\n"
    assert app1_content == expected_app1, f"Content of '{app1_path}' is incorrect. Expected: {expected_app1}, Got: {app1_content}"
    assert db_content == expected_db, f"Content of '{db_path}' is incorrect. Expected: {expected_db}, Got: {db_content}"


def test_c_program_exists():
    assert os.path.isfile(SOURCE), f"Expected C source file '{SOURCE}' is missing."
    assert os.path.isfile(BINARY), f"Expected compiled binary '{BINARY}' is missing."
    assert os.access(BINARY, os.X_OK), f"Expected binary '{BINARY}' to be executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted config_server must be a compiled ELF executable."


def test_server_unauthorized():
    proc = start_server(BINARY)
    try:
        response = requests.get(SERVER_URL, timeout=2)
        assert response.status_code == 401, f"Expected status code 401 for missing auth header, got {response.status_code}. Response: {response.text}"
        response = requests.get(SERVER_URL, headers={"X-Auth-Key": AUTH_KEY + "-wrong"}, timeout=2)
        assert response.status_code == 401, f"Expected status code 401 for an incorrect auth key, got {response.status_code}."
    finally:
        stop_server(proc)


def test_server_authorized_manifest():
    proc = start_server(BINARY)
    try:
        response = requests.get(SERVER_URL, headers={"X-Auth-Key": AUTH_KEY}, timeout=2)
        assert response.status_code == 200, f"Expected status code 200 for valid auth header, got {response.status_code}. Response: {response.text}"
        expected_manifest = get_expected_manifest()
        actual_manifest = response.text.strip()
        assert actual_manifest == expected_manifest, f"Manifest content is incorrect.\nExpected:\n{expected_manifest}\n\nGot:\n{actual_manifest}"
    finally:
        stop_server(proc)


def exercise_dynamic_manifest(executable):
    proc = start_server(executable)
    app1_path = os.path.join(CONFIG_DIR, "app1.conf")
    with open(app1_path, "rb") as f:
        original_app1 = f.read()
    token = uuid.uuid4().hex
    added_name = f"runtime_{token}.conf"
    added_path = os.path.join(CONFIG_DIR, added_name)
    ignored_path = os.path.join(CONFIG_DIR, f"runtime_{token}.txt")
    nested_dir = os.path.join(CONFIG_DIR, f"nested_{token}")
    os.mkdir(nested_dir)
    nested_path = os.path.join(nested_dir, "ignored.conf")
    try:
        with open(app1_path, "wb") as f:
            f.write(original_app1 + ("runtime_change=" + token + "\n").encode())
        with open(added_path, "wb") as f:
            f.write(os.urandom(41) + token.encode())
        with open(ignored_path, "wb") as f:
            f.write(b"must not appear")
        with open(nested_path, "wb") as f:
            f.write(b"must not appear")

        response = requests.get(SERVER_URL, headers={"X-Auth-Key": AUTH_KEY}, timeout=2)
        assert response.status_code == 200
        assert response.text.strip() == manifest_from_disk()

        with open(added_path, "ab") as f:
            f.write(b"\nsecond-change-" + os.urandom(17))
        response = requests.get(SERVER_URL, headers={"X-Auth-Key": AUTH_KEY}, timeout=2)
        assert response.status_code == 200
        assert response.text.strip() == manifest_from_disk(), "Manifest was not recomputed after a live configuration change."
    finally:
        with open(app1_path, "wb") as f:
            f.write(original_app1)
        for path in (added_path, ignored_path, nested_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        try:
            os.rmdir(nested_dir)
        except FileNotFoundError:
            pass
        stop_server(proc)


def test_installed_binary_generates_manifest_dynamically():
    exercise_dynamic_manifest(BINARY)


def test_source_compiles_and_rebuilt_c_server_works():
    rebuilt = f"/tmp/config_server_rebuilt_{uuid.uuid4().hex}"
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", rebuilt, "-lmicrohttpd", "-pthread"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"C source did not compile successfully:\n{result.stderr}"
    try:
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        exercise_dynamic_manifest(rebuilt)
    finally:
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
