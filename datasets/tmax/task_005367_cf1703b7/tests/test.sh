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
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import io
import json
import os
import random
import re
import shutil
import signal
import socket
import string
import subprocess
import tarfile
import tempfile
import time
import zipfile

import requests

BASE_URL = "http://127.0.0.1:9090"
TOKEN = "AUTH-TOKEN-77X9-B2C4"
ARCHIVE = "/app/server_backup.tar.gz"


def request(path, headers=None, timeout=5):
    try:
        return requests.get(BASE_URL + path, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        raise AssertionError(f"Failed to connect to {BASE_URL}{path}: {exc}")


def check_original_assertions():
    response = request("/health")
    assert response.status_code == 200, f"Expected status code 200 for /health, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Expected JSON response for /health, got: {response.text}")
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}} for /health, got {data}"

    response = request("/largest")
    assert response.status_code == 401, f"Expected status code 401 for /largest without auth, got {response.status_code}"

    response = request("/largest", {"Authorization": "Bearer WRONG-TOKEN"})
    assert response.status_code == 401, f"Expected status code 401 for /largest with wrong auth, got {response.status_code}"

    response = request("/largest", {"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200, (
        f"Expected status code 200 for /largest with correct auth, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Expected JSON response for /largest, got: {response.text}")
    assert isinstance(data, list), f"Expected JSON array for /largest, got {type(data)}"
    assert len(data) == 3, f"Expected exactly 3 items in the array, got {len(data)}"
    expected = [
        {"path": "logs_2023.zip/db.dump", "size": 750000},
        {"path": "logs_2023.zip/app.log", "size": 210000},
        {"path": "logs_2022.zip/auth.log", "size": 85000},
    ]
    assert data == expected, f"Expected top 3 largest files to be {expected}, but got {data}"


def listening_pids(port=9090):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.append(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def wait_ready(timeout=12):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL + "/health", timeout=0.5)
            if response.status_code == 200:
                return
            last = f"HTTP {response.status_code}"
        except requests.exceptions.RequestException as exc:
            last = str(exc)
        time.sleep(0.1)
    raise AssertionError(f"Restarted submitted server did not become ready: {last}")


def make_archive(path):
    suffix = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=10))
    zip_a = f"fresh_{suffix}.zip"
    zip_b = f"older_{suffix}.zip"
    entries = [
        (zip_a, f"database_{suffix}.dat", 431123),
        (zip_b, f"application_{suffix}.log", 287019),
        (zip_a, f"security_{suffix}.log", 163777),
        (zip_b, f"worker_{suffix}.log", 91013),
        (zip_a, f"cache_{suffix}.dat", 12011),
    ]

    grouped = {}
    for zip_name, file_name, size in entries:
        grouped.setdefault(zip_name, []).append((file_name, size))

    with tarfile.open(path, "w:gz") as outer:
        for zip_name, members in grouped.items():
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as nested:
                for file_name, size in members:
                    nested.writestr(file_name, os.urandom(size))
            payload = buffer.getvalue()
            info = tarfile.TarInfo(zip_name)
            info.size = len(payload)
            info.mode = 0o644
            outer.addfile(info, io.BytesIO(payload))

    ordered = sorted(entries, key=lambda item: item[2], reverse=True)[:3]
    return [{"path": f"{z}/{f}", "size": size} for z, f, size in ordered]


def main():
    # Retain all checks made by the original verifier against the delivered service.
    check_original_assertions()

    pids = listening_pids()
    assert pids, "No process is listening on 127.0.0.1:9090"
    pid = pids[0]

    with tempfile.TemporaryDirectory(prefix="verifier-") as temp:
        submitted_binary = os.path.join(temp, "submitted-server")
        shutil.copyfile(f"/proc/{pid}/exe", submitted_binary)
        os.chmod(submitted_binary, 0o755)

        build_info = subprocess.run(
            ["go", "version", "-m", submitted_binary],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        assert build_info.returncode == 0 and re.search(r"\bgo\d+\.\d+", build_info.stdout), (
            "The process serving port 9090 is not a compiled Go program"
        )

        binary_data = open(submitted_binary, "rb").read()
        for package in (b"archive/tar", b"compress/gzip", b"archive/zip"):
            assert package in binary_data, f"The Go server does not include required package {package.decode()}"

        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            cwd = "/app"
        try:
            raw_args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
            extra_args = [os.fsdecode(arg) for arg in raw_args[1:] if arg]
        except OSError:
            extra_args = []

        archive_backup = os.path.join(temp, "server_backup.original.tar.gz")
        shutil.copy2(ARCHIVE, archive_backup)
        restarted = None
        try:
            # Stop the original listener, replace the archive with an unpredictable case,
            # and execute the submitted Go artifact itself against that case.
            for old_pid in listening_pids():
                try:
                    os.kill(old_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            deadline = time.time() + 5
            while listening_pids() and time.time() < deadline:
                time.sleep(0.05)
            for old_pid in listening_pids():
                try:
                    os.kill(old_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            time.sleep(0.1)

            expected = make_archive(ARCHIVE)
            env = os.environ.copy()
            env["TMPDIR"] = os.path.join(temp, "tmp")
            os.mkdir(env["TMPDIR"])
            restarted = subprocess.Popen(
                [submitted_binary] + extra_args,
                cwd=cwd if os.path.isdir(cwd) else "/app",
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wait_ready()

            response = request("/largest")
            assert response.status_code == 401, "Dynamic /largest request was not protected without authentication"
            response = request("/largest", {"Authorization": "Bearer WRONG-TOKEN"})
            assert response.status_code == 401, "Dynamic /largest request accepted an incorrect token"
            response = request("/largest", {"Authorization": f"Bearer {TOKEN}"}, timeout=15)
            assert response.status_code == 200, f"Dynamic /largest returned HTTP {response.status_code}: {response.text}"
            try:
                actual = response.json()
            except ValueError:
                raise AssertionError(f"Dynamic /largest did not return JSON: {response.text}")
            assert actual == expected, f"Server did not derive top files from the replacement nested archive: expected {expected}, got {actual}"
        finally:
            if restarted is not None and restarted.poll() is None:
                restarted.terminate()
                try:
                    restarted.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    restarted.kill()
                    restarted.wait(timeout=3)
            shutil.copy2(archive_backup, ARCHIVE)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
