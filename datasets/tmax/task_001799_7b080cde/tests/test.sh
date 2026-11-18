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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

PROJECT = Path("/home/user/translation_service")
DYNAMIC = {"fr": [], "ja": []}
SERVICE_PROCESS = None


def kill_port_9000():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "2328" and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc_dir.name))
                    break
        except (OSError, PermissionError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def build_rust_binary():
    assert PROJECT.is_dir(), f"Missing Rust project directory: {PROJECT}"
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"
    assert (PROJECT / "src/main.rs").is_file(), "src/main.rs is missing"

    result = subprocess.run(
        ["cargo", "build", "--message-format=json"],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=240,
    )
    assert result.returncode == 0, f"Rust application failed to build:\n{result.stdout}\n{result.stderr}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
            executable = message.get("executable")
            if executable:
                executables.append(executable)
    assert executables, "Cargo did not produce a Rust binary target"
    binary = Path(executables[-1])
    assert binary.is_file() and os.access(binary, os.X_OK), "Built Rust binary is missing or not executable"
    return binary


def redis(*args):
    result = subprocess.run(["redis-cli", "--raw", *args], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"redis-cli failed: {result.stderr}"
    return result.stdout.rstrip("\n")


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global SERVICE_PROCESS

    try:
        requests.get("http://127.0.0.1:8080/fr.csv", timeout=3).raise_for_status()
    except requests.RequestException as exc:
        pytest.fail(f"Legacy HTTP service is not running on port 8080: {exc}")
    assert redis("PING") == "PONG", "Redis is not running on port 6379"

    token = secrets.token_hex(8).upper()
    fr_count = 2 + secrets.randbelow(3)
    ja_count = 2 + secrets.randbelow(3)
    DYNAMIC["fr"] = [(f"FR_{token}_{i}", f"Café-{token}-{i}") for i in range(fr_count)]
    DYNAMIC["ja"] = [(f"JA_{token}_{i}", f"動的-{token}-{i}") for i in range(ja_count)]

    fr_rows = [("WELCOME", "Bienvenue"), ("FAREWELL", "Au revoir"), *DYNAMIC["fr"]]
    ja_rows = [("GREETING", "こんにちは"), ("FAREWELL", "さようなら"), *DYNAMIC["ja"]]
    Path("/app/legacy_files/fr.csv").write_bytes(
        ("\n".join(f"{key},{value}" for key, value in fr_rows) + "\n").encode("iso-8859-1")
    )
    Path("/app/legacy_files/ja.csv").write_bytes(
        ("\n".join(f"{key},{value}" for key, value in ja_rows) + "\n").encode("shift_jis")
    )

    kill_port_9000()
    assert redis("FLUSHALL") == "OK", "Could not clear Redis before rerunning the ETL"
    binary = build_rust_binary()

    output = open("/tmp/translation_service_verifier.log", "wb")
    SERVICE_PROCESS = subprocess.Popen(
        [str(binary)],
        cwd=PROJECT,
        stdout=output,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    probe_key, probe_value = DYNAMIC["ja"][0]
    deadline = time.time() + 35
    last_error = None
    while time.time() < deadline:
        if SERVICE_PROCESS.poll() is not None:
            pytest.fail(f"Built Rust service exited with status {SERVICE_PROCESS.returncode}")
        try:
            response = requests.get(f"http://127.0.0.1:9000/translate/ja/{probe_key}", timeout=2)
            if response.status_code == 200 and response.text == probe_value:
                break
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.5)
    else:
        pytest.fail(f"Rerun Rust service did not serve freshly generated ETL data: {last_error}")

    yield


def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "[SUCCESS] Processed fr - 2 keys loaded." in content, "Missing or incorrect log entry for 'fr' in pipeline.log."
    assert "[SUCCESS] Processed ja - 2 keys loaded." in content, "Missing or incorrect log entry for 'ja' in pipeline.log."
    assert f"[SUCCESS] Processed fr - {2 + len(DYNAMIC['fr'])} keys loaded." in content
    assert f"[SUCCESS] Processed ja - {2 + len(DYNAMIC['ja'])} keys loaded." in content


def test_translation_api_ja():
    url = "http://127.0.0.1:9000/translate/ja/GREETING"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Rust service at {url}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK for {url}, got {resp.status_code}"
    assert resp.text == "こんにちは", f"Expected 'こんにちは', got '{resp.text}'"

    url_farewell = "http://127.0.0.1:9000/translate/ja/FAREWELL"
    resp = requests.get(url_farewell, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for {url_farewell}, got {resp.status_code}"
    assert resp.text == "さようなら", f"Expected 'さようなら', got '{resp.text}'"


def test_translation_api_fr():
    url = "http://127.0.0.1:9000/translate/fr/WELCOME"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Rust service at {url}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK for {url}, got {resp.status_code}"
    assert resp.text == "Bienvenue", f"Expected 'Bienvenue', got '{resp.text}'"

    url_farewell = "http://127.0.0.1:9000/translate/fr/FAREWELL"
    resp = requests.get(url_farewell, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for {url_farewell}, got {resp.status_code}"
    assert resp.text == "Au revoir", f"Expected 'Au revoir', got '{resp.text}'"


def test_translation_api_not_found():
    url = "http://127.0.0.1:9000/translate/fr/UNKNOWN_KEY"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Rust service at {url}: {e}")

    assert resp.status_code == 404, f"Expected 404 Not Found for {url}, got {resp.status_code}"


def test_fresh_etl_data_is_decoded_and_cached_in_redis():
    for lang, entries in DYNAMIC.items():
        for key, expected in entries:
            redis_key = f"locale:{lang}:{key}"
            assert redis("GET", redis_key) == expected, f"Fresh ETL value missing from Redis: {redis_key}"
            response = requests.get(f"http://127.0.0.1:9000/translate/{lang}/{key}", timeout=5)
            assert response.status_code == 200
            assert response.text == expected


def test_api_queries_redis_and_dynamic_missing_key_is_404():
    key, _ = DYNAMIC["fr"][0]
    replacement = f"Redis-update-{secrets.token_hex(6)}"
    assert redis("SET", f"locale:fr:{key}", replacement) == "OK"
    response = requests.get(f"http://127.0.0.1:9000/translate/fr/{key}", timeout=5)
    assert response.status_code == 200
    assert response.text == replacement, "API did not query the current Redis value"

    missing = f"MISSING_{secrets.token_hex(10).upper()}"
    response = requests.get(f"http://127.0.0.1:9000/translate/ja/{missing}", timeout=5)
    assert response.status_code == 404
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
