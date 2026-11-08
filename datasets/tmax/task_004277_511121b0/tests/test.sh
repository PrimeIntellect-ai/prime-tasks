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
import base64
import codecs
import hashlib
import json
import os
import random
import secrets
import signal
import string
import subprocess
import time
import zlib

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:8080/process"
PROJECT_DIR = "/home/user/encoder_service"
SCRIPT_PATH = "/home/user/build_and_run.sh"


def crc32_hex(s: str) -> str:
    return f"{zlib.crc32(s.encode('utf-8')) & 0xFFFFFFFF:08x}"


def expected_legacy(v: str, payload: str) -> str:
    crc = crc32_hex(payload)
    rot13 = codecs.encode(payload, "rot_13")
    hex_str = "".join(f"{ord(c):02x}" for c in rot13)
    sorted_hex = "".join(sorted(hex_str))
    return f"LEGACY_{v}_{crc}_{sorted_hex}"


def expected_modern(v: str, payload: str) -> str:
    crc = crc32_hex(payload)
    b32 = base64.b32encode(payload.encode("utf-8")).decode("utf-8").rstrip("=")
    return f"V_{v}_CRC_{crc}_{b32}"


def make_request(v: str, payload: str) -> str:
    try:
        resp = requests.post(SERVICE_URL, json={"v": v, "payload": payload}, timeout=3)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {SERVICE_URL}: {exc}")

    assert resp.status_code == 200, (
        f"Expected status 200, got {resp.status_code}. Response body: {resp.text}"
    )
    text = resp.text.strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1]
    return text


def listening_pids():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state = fields[1], fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_service():
    pids = listening_pids()
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids():
        time.sleep(0.1)
    for pid in listening_pids():
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids():
        time.sleep(0.1)
    assert not listening_pids(), "Could not stop the pre-existing service on port 8080"


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_listener_is_release_rust_binary():
    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert metadata.returncode == 0, f"cargo metadata failed: {metadata.stderr}"
    data = json.loads(metadata.stdout)
    target_dir = data["target_directory"]
    bin_names = {
        target["name"]
        for package in data["packages"]
        for target in package["targets"]
        if "bin" in target["kind"]
    }
    assert bin_names, "The Cargo project has no binary target"

    release_bins = []
    for name in bin_names:
        path = os.path.join(target_dir, "release", name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            release_bins.append(path)
    assert release_bins, "No release-mode Rust binary was produced"

    expected_hashes = {sha256_file(path) for path in release_bins}
    pids = listening_pids()
    assert pids, "No process is listening on 127.0.0.1:8080 after running the script"
    listener_hashes = set()
    for pid in pids:
        try:
            listener_hashes.add(sha256_file(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert listener_hashes & expected_hashes, (
        "The process listening on port 8080 is not a release binary from the Rust project"
    )


def test_build_and_run_script_exists_and_works():
    assert os.path.exists(SCRIPT_PATH), f"Missing build script at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Build script at {SCRIPT_PATH} must be executable"

    stop_existing_service()

    source_path = "/app/integration_tester.c"
    with open(source_path, "rb") as f:
        original_source = f.read()

    token = secrets.token_hex(24)
    marker = f"/tmp/integration_probe_{secrets.token_hex(12)}"
    probe_source = f'''#include <stdio.h>
#include <curl/curl.h>
int main(void) {{
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != 0) return 20;
    CURL *handle = curl_easy_init();
    if (!handle) return 21;
    curl_easy_cleanup(handle);
    curl_global_cleanup();
    FILE *f = fopen({json.dumps(marker)}, "w");
    if (!f) return 22;
    fputs({json.dumps(token)}, f);
    fclose(f);
    return 0;
}}
'''

    try:
        with open(source_path, "w") as f:
            f.write(probe_source)
        log_path = f"/tmp/build_and_run_{secrets.token_hex(8)}.log"
        with open(log_path, "w") as log:
            result = subprocess.run(
                [SCRIPT_PATH],
                cwd="/home/user",
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=240,
            )
        log_text = open(log_path, errors="replace").read()
        assert result.returncode == 0, f"build_and_run.sh failed:\n{log_text}"
        assert os.path.exists(marker), (
            "build_and_run.sh did not compile and execute the current integration_tester.c"
        )
        assert open(marker).read() == token, "The compiled C integration probe did not run correctly"
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        if os.path.exists(marker):
            os.unlink(marker)

    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            requests.post(SERVICE_URL, json={"v": "2.0.0", "payload": "ready"}, timeout=0.5)
            break
        except requests.RequestException:
            time.sleep(0.2)
    else:
        pytest.fail("Service did not become available after build_and_run.sh completed")

    assert_listener_is_release_rust_binary()


def test_rust_project_exists():
    path = "/home/user/encoder_service/Cargo.toml"
    assert os.path.exists(path), f"Missing Rust project configuration at {path}"


@pytest.mark.parametrize("v,payload", [
    ("1.5.2", "test_data"),
    ("0.9.9", "hello"),
    ("1.9.99", "ComplexPayload123!@#"),
])
def test_legacy_logic(v, payload):
    expected = expected_legacy(v, payload)
    actual = make_request(v, payload)
    assert actual == expected, (
        f"Legacy logic failed for v={v}, payload={payload}. Expected {expected}, got {actual}"
    )


@pytest.mark.parametrize("v,payload", [
    ("2.0.0", "test_data"),
    ("2.1.0", "hello"),
    ("10.0.5", "ComplexPayload123!@#"),
])
def test_modern_logic(v, payload):
    expected = expected_modern(v, payload)
    actual = make_request(v, payload)
    assert actual == expected, (
        f"Modern logic failed for v={v}, payload={payload}. Expected {expected}, got {actual}"
    )


def test_runtime_generated_versions_and_payloads():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " _-.:/+!@#$%^&*()[]{}?,="

    cases = [
        ("0.0.0", ""),
        ("1.999.999", "boundary below two"),
        ("2.0.0", ""),
        ("2.0.1", "boundary above two"),
    ]
    for _ in range(14):
        major = rng.choice([0, 1])
        version = f"{major}.{rng.randrange(0, 10000)}.{rng.randrange(0, 10000)}"
        payload = "".join(secrets.choice(alphabet) for _ in range(rng.randrange(1, 97)))
        cases.append((version, payload))
    for _ in range(14):
        version = f"{rng.randrange(2, 51)}.{rng.randrange(0, 10000)}.{rng.randrange(0, 10000)}"
        payload = "".join(secrets.choice(alphabet) for _ in range(rng.randrange(1, 97)))
        cases.append((version, payload))

    rng.shuffle(cases)
    for version, payload in cases:
        expected = (
            expected_legacy(version, payload)
            if int(version.split(".", 1)[0]) < 2
            else expected_modern(version, payload)
        )
        actual = make_request(version, payload)
        assert actual == expected, (
            f"Generated case failed for v={version}, payload={payload!r}. "
            f"Expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
