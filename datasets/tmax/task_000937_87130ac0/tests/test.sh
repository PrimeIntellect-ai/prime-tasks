#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request

ROOT = "/home/user/workspace"
DATA_DIR = ROOT + "/data"
CONFIG = ROOT + "/config/settings.json"
SOURCE_DIR = ROOT + "/disk_monitor"
SOURCE = SOURCE_DIR + "/main.go"
GO_MOD = SOURCE_DIR + "/go.mod"
BINARY = SOURCE_DIR + "/monitor_service"
SCRIPT = ROOT + "/check_conn.sh"
LOG = ROOT + "/monitor_results.log"
URL = "http://127.0.0.1:8080/status"
EXPECTED_KEYS = {"status", "usage_mb", "quota_mb"}


def fetch_status(retries=1):
    last_error = None
    for _ in range(retries):
        try:
            req = urllib.request.Request(URL, method="GET")
            with urllib.request.urlopen(req, timeout=2) as response:
                raw = response.read()
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                data = json.loads(raw.decode("utf-8"))
                assert isinstance(data, dict), "Status response must be a JSON object."
                assert set(data) == EXPECTED_KEYS, f"Status response has incorrect keys: {set(data)}"
                return raw, data
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Could not obtain a valid status response: {last_error}")


def listening_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port_8080():
    for _ in range(30):
        inodes = listening_inodes()
        if not inodes:
            return
        victims = set()
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == os.getpid():
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
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
        for pid in victims:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    if listening_inodes():
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == os.getpid():
                continue
            try:
                for fd in os.listdir(f"/proc/{entry}/fd"):
                    target = os.readlink(f"/proc/{entry}/fd/{fd}")
                    if target.startswith("socket:[") and target[8:-1] in listening_inodes():
                        os.kill(int(entry), signal.SIGKILL)
                        break
            except (OSError, ProcessLookupError):
                pass
        time.sleep(0.2)
    assert not listening_inodes(), "Could not free 127.0.0.1:8080 for behavioral testing."


def launch(path):
    proc = subprocess.Popen(
        [path], cwd=SOURCE_DIR, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        raw, data = fetch_status(retries=50)
    except Exception:
        if proc.poll() is None:
            proc.terminate()
        raise
    return proc, raw, data


def total_usage_mb():
    total = 0
    for base, _, names in os.walk(DATA_DIR):
        for name in names:
            path = os.path.join(base, name)
            if os.path.isfile(path):
                total += os.path.getsize(path)
    return total // 1048576


def assert_status(data, usage, quota):
    assert data["status"] == "ok", "Expected status to be 'ok'."
    assert type(data["usage_mb"]) is int, "usage_mb must be an integer."
    assert type(data["quota_mb"]) is int, "quota_mb must be an integer."
    assert data["usage_mb"] == usage, f"Expected usage_mb={usage}, got {data['usage_mb']}."
    assert data["quota_mb"] == quota, f"Expected quota_mb={quota}, got {data['quota_mb']}."


def run_script():
    return subprocess.run([SCRIPT], cwd=ROOT, timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_01_dummy_file():
    path = DATA_DIR + "/dummy.dat"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.getsize(path) == 5242880, f"File {path} must be exactly 5242880 bytes."


def test_02_config_file():
    assert os.path.exists(CONFIG), f"File {CONFIG} does not exist."
    with open(CONFIG, "r") as f:
        data = json.load(f)
    assert set(data) == {"monitor_dir", "quota_mb"}, "settings.json must contain exactly the two required keys."
    assert data["monitor_dir"] == DATA_DIR, "monitor_dir key is incorrect."
    assert data["quota_mb"] == 15, "quota_mb key is incorrect."


def test_03_go_source_module_and_binary():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist."
    assert os.path.isfile(GO_MOD), f"Go module file {GO_MOD} does not exist."
    with open(GO_MOD, "r") as f:
        module_lines = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("//")]
    assert module_lines and re.fullmatch(r"module\s+monitor", module_lines[0]), "go.mod must declare module monitor."
    assert os.path.isfile(BINARY), f"Go binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Go binary {BINARY} is not executable."
    info = subprocess.run(["go", "version", "-m", BINARY], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert info.returncode == 0, "monitor_service is not recognized as a Go-built executable."
    assert re.search(r"(?m)^\s*path\s+monitor\s*$", info.stdout), "monitor_service was not built from module monitor."


def test_04_initial_http_service():
    _, data = fetch_status(retries=10)
    assert_status(data, 5, 15)


def test_05_bash_script_and_existing_log():
    assert os.path.isfile(SCRIPT), f"Bash script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Bash script {SCRIPT} is not executable."
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r") as f:
        data = json.loads(f.read().strip())
    assert data.get("status") == "ok", "Log JSON status is incorrect."
    assert data.get("usage_mb") == 5, "Log JSON usage_mb is incorrect."
    assert data.get("quota_mb") == 15, "Log JSON quota_mb is incorrect."

    expected_raw, _ = fetch_status()
    result = run_script()
    assert result.returncode == 0, f"Diagnostic script failed: {result.stderr.decode(errors='replace')}"
    with open(LOG, "rb") as f:
        assert f.read() == expected_raw, "Diagnostic script must write strictly the raw /status response body to the log."


def test_06_dynamic_binary_source_and_diagnostics():
    with open(CONFIG, "rb") as f:
        original_config = f.read()
    extra = DATA_DIR + "/verifier_dynamic.dat"
    rebuilt = "/tmp/monitor_source_build"
    submitted_proc = None
    rebuilt_proc = None
    try:
        kill_port_8080()
        try:
            os.remove(LOG)
        except FileNotFoundError:
            pass
        run_script()
        if os.path.exists(LOG):
            with open(LOG, "rb") as f:
                stale = f.read()
            try:
                stale_data = json.loads(stale.decode("utf-8"))
            except Exception:
                stale_data = None
            assert not (isinstance(stale_data, dict) and stale_data.get("status") == "ok"), "Diagnostic script fabricated a successful response while port 8080 was closed."

        quota1 = 31 + secrets.randbelow(50)
        size1 = 1048576 + secrets.randbelow(3 * 1048576) + 123
        with open(extra, "wb") as f:
            f.truncate(size1)
        with open(CONFIG, "w") as f:
            json.dump({"monitor_dir": DATA_DIR, "quota_mb": quota1}, f)
        expected1 = total_usage_mb()
        submitted_proc, expected_raw, data = launch(BINARY)
        assert_status(data, expected1, quota1)

        result = run_script()
        assert result.returncode == 0, f"Diagnostic script failed against the live service: {result.stderr.decode(errors='replace')}"
        with open(LOG, "rb") as f:
            assert f.read() == expected_raw, "Diagnostic script did not fetch and log the randomized live response."

        kill_port_8080()
        submitted_proc = None
        build = subprocess.run(["go", "build", "-o", rebuilt, "."], cwd=SOURCE_DIR, timeout=60,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert build.returncode == 0, f"main.go does not build successfully: {build.stderr.decode(errors='replace')}"

        quota2 = 82 + secrets.randbelow(70)
        with open(extra, "wb") as f:
            f.truncate(size1 + 2 * 1048576 + 777)
        with open(CONFIG, "w") as f:
            json.dump({"monitor_dir": DATA_DIR, "quota_mb": quota2}, f)
        expected2 = total_usage_mb()
        rebuilt_proc, _, data = launch(rebuilt)
        assert_status(data, expected2, quota2)
    finally:
        kill_port_8080()
        try:
            os.remove(extra)
        except FileNotFoundError:
            pass
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        final_proc, final_raw, final_data = launch(BINARY)
        assert_status(final_data, 5, 15)
        result = run_script()
        assert result.returncode == 0, "Diagnostic script failed while restoring the required final state."
        with open(LOG, "rb") as f:
            assert f.read() == final_raw, "Final diagnostic log is not the raw service response."

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
