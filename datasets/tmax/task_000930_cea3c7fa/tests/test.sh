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
import random
import secrets
import signal
import struct
import subprocess
import time
import zlib
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw

BASE_URL = "http://127.0.0.1:8000"
API_KEY = "9fXb2_Qz1"


def get(path, key=None):
    headers = {} if key is None else {"Authorization": key}
    try:
        return requests.get(f"{BASE_URL}{path}", headers=headers, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the API at {BASE_URL}{path}: {exc}")


def test_missing_auth():
    response = get("/config/network")
    assert response.status_code == 403, (
        f"Expected HTTP 403 Forbidden for missing auth, got "
        f"{response.status_code}. Response: {response.text}"
    )


def test_invalid_auth():
    response = get("/config/network", "wrong_salt")
    assert response.status_code == 403, (
        f"Expected HTTP 403 Forbidden for invalid auth, got "
        f"{response.status_code}. Response: {response.text}"
    )


def test_valid_auth_existing_module_network():
    response = get("/config/network", API_KEY)
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for valid auth, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = [
        {"time": 1696161000, "user": "alice", "changes": ["+ dns=8.8.8.8"]},
        {"time": 1696165000, "user": "charlie", "changes": ["+ ip_forwarding=1"]},
    ]
    assert data == expected_data, f"Expected JSON data {expected_data}, got {data}"


def test_valid_auth_existing_module_database():
    response = get("/config/database", API_KEY)
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for valid auth, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = [
        {
            "time": 1696162500,
            "user": "bob",
            "changes": ["- max_conn=100", "+ max_conn=500"],
        }
    ]
    assert data == expected_data, f"Expected JSON data {expected_data}, got {data}"


def test_valid_auth_non_existent_module():
    response = get("/config/unknown_module", API_KEY)
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for valid auth but unknown module, got "
        f"{response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data == [], f"Expected empty list [] for unknown module, got {data}"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if int(local_address.rsplit(":", 1)[1], 16) == 8000 and state == "0A":
                inodes.add(fields[9])

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return int(proc.name)
    return None


def capture_server():
    pid = listener_pid()
    assert pid is not None, "No process is listening on port 8000"
    proc = Path(f"/proc/{pid}")
    argv = [x.decode(errors="surrogateescape") for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
    assert argv, "Could not determine the server command"
    cwd = os.readlink(proc / "cwd")
    env = os.environ.copy()
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, env


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 4
    while time.time() < deadline:
        if listener_pid() is None:
            return
        time.sleep(0.1)
    pid = listener_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.1)


def start_server(argv, cwd, env):
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Submitted server exited during restart with status {process.returncode}")
        if listener_pid() is not None:
            try:
                requests.get(BASE_URL + "/config/readiness_probe", timeout=1)
                return process
            except requests.RequestException:
                pass
        time.sleep(0.2)
    pytest.fail("Submitted server did not restart on 127.0.0.1:8000")


def write_challenge(secret):
    image = Image.new("RGB", (400, 100), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.text((10, 10), f"API_SALT: {secret}", fill=(0, 0, 0))
    image.save("/app/legacy_dashboard.png")

    suffix = secrets.token_hex(4)
    modules = [f"net_{suffix}", f"db_{suffix}", f"auth_{suffix}"]
    users = [f"user_{secrets.token_hex(2)}" for _ in range(7)]
    timestamps = random.sample(range(1800000000, 1900000000), 7)
    records = []
    for index in range(7):
        module = modules[index % len(modules)]
        changes = [
            ("+" if (index + j) % 2 == 0 else "-")
            + f" option_{index}_{j}={secrets.token_hex(3)}"
            for j in range(1 + index % 3)
        ]
        records.append(
            "===CONFIG_CHANGE===\n"
            f"Time: {timestamps[index]}\n"
            f"User: {users[index]}\n"
            f"Module: {module}\n"
            "---\n"
            + "\n".join(changes)
            + "\n===================\n"
        )

    random.shuffle(records)
    raw = "".join(records).encode("utf-8")
    cuts = sorted(random.sample(range(1, len(raw)), 5))
    chunks = []
    previous = 0
    for cut in cuts + [len(raw)]:
        chunks.append(raw[previous:cut])
        previous = cut

    with open("/app/config_archive.lzc", "wb") as archive:
        archive.write(b"LZC1")
        for chunk in chunks:
            compressed = zlib.compress(chunk)
            archive.write(struct.pack(">I", len(compressed)))
            archive.write(compressed)

    return modules


def derive_expected_from_archive():
    blob = Path("/app/config_archive.lzc").read_bytes()
    assert blob[:4] == b"LZC1"
    offset = 4
    raw = bytearray()
    while offset < len(blob):
        assert offset + 4 <= len(blob)
        size = struct.unpack(">I", blob[offset:offset + 4])[0]
        offset += 4
        assert offset + size <= len(blob)
        raw.extend(zlib.decompress(blob[offset:offset + size]))
        offset += size

    result = {}
    text = raw.decode("utf-8")
    for block in text.split("===CONFIG_CHANGE===\n")[1:]:
        lines = block.splitlines()
        assert lines[0].startswith("Time: ")
        assert lines[1].startswith("User: ")
        assert lines[2].startswith("Module: ")
        assert lines[3] == "---"
        end = lines.index("===================")
        module = lines[2][len("Module: "):]
        item = {
            "time": int(lines[0][len("Time: "):]),
            "user": lines[1][len("User: "):],
            "changes": lines[4:end],
        }
        result.setdefault(module, []).append(item)
    for values in result.values():
        values.sort(key=lambda item: item["time"])
    return result


def test_randomized_source_recovery():
    argv, cwd, env = capture_server()
    image_path = Path("/app/legacy_dashboard.png")
    archive_path = Path("/app/config_archive.lzc")
    original_image = image_path.read_bytes()
    original_archive = archive_path.read_bytes()
    secret = "K" + "".join(secrets.choice("23456789") for _ in range(10))

    stop_listener()
    try:
        modules = write_challenge(secret)
        expected = derive_expected_from_archive()
        start_server(argv, cwd, env)

        response = get(f"/config/{modules[0]}")
        assert response.status_code == 403, "Randomized data must still require authentication"
        response = get(f"/config/{modules[0]}", API_KEY)
        assert response.status_code == 403, "The old hardcoded API key must be rejected"

        for module in modules:
            response = get(f"/config/{module}", secret)
            assert response.status_code == 200, response.text
            try:
                actual = response.json()
            except ValueError:
                pytest.fail(f"Response is not valid JSON: {response.text}")
            assert actual == expected[module], (
                f"Incorrect recovered records for randomized module {module}: "
                f"expected {expected[module]}, got {actual}"
            )

        unknown = f"missing_{secrets.token_hex(5)}"
        response = get(f"/config/{unknown}", secret)
        assert response.status_code == 200, response.text
        assert response.json() == []
    finally:
        stop_listener()
        image_path.write_bytes(original_image)
        archive_path.write_bytes(original_archive)
        start_server(argv, cwd, env)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
