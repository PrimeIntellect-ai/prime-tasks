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
import pathlib
import signal
import subprocess
import time
import uuid

import requests

UNLOCK = "/app/fw_unlock"
EXPECT_SCRIPT = "/home/user/unlock.exp"
SOURCE = "/home/user/monitor_service.c"
BINARY = "/home/user/monitor_service"
FLAG = "/tmp/fw_unlocked"
EXPECTED_PIN = None
RUNNING_SERVICE = None


def derive_pin():
    global EXPECTED_PIN
    if EXPECTED_PIN is not None:
        return EXPECTED_PIN

    for value in range(10000):
        candidate = f"{value:04d}"
        try:
            result = subprocess.run(
                [UNLOCK], input=candidate + "\n", text=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=1, check=False,
            )
        except subprocess.TimeoutExpired:
            continue
        if result.returncode == 0:
            EXPECTED_PIN = candidate
            if os.path.exists(FLAG):
                os.unlink(FLAG)
            return candidate
    raise AssertionError("Could not derive the emergency PIN from the supplied unlock program")


def run_expect_script():
    return subprocess.run(
        ["/usr/bin/expect", EXPECT_SCRIPT],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=10, check=False,
    )


def listener_inodes(port=8080):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                found.add(fields[9])
    return found


def kill_port_8080():
    inodes = listener_inodes()
    if not inodes:
        return
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
                    try:
                        os.kill(int(entry), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.3)


def start_service(path):
    kill_port_8080()
    proc = subprocess.Popen(
        [path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL, start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Service {path} exited early with status {proc.returncode}")
        try:
            response = requests.get("http://127.0.0.1:8080/status", timeout=0.5)
            return proc, response
        except requests.exceptions.RequestException:
            time.sleep(0.1)
    proc.kill()
    raise AssertionError(f"Service {path} did not listen on 127.0.0.1:8080")


def assert_valid_status_response(response):
    assert response.status_code == 200, f"Expected HTTP status 200, got {response.status_code}"
    assert response.raw.version == 11, "Response was not HTTP/1.1"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "UP", f"Expected status 'UP', got {data.get('status')}"
    assert data.get("auth") == derive_pin(), f"Expected auth PIN derived from fw_unlock, got {data.get('auth')}"


def assert_not_catchall_success():
    invalid = "/" + uuid.uuid4().hex
    try:
        response = requests.get("http://127.0.0.1:8080" + invalid, timeout=1)
    except requests.exceptions.RequestException:
        return
    if response.status_code == 200:
        try:
            data = response.json()
        except ValueError:
            return
        assert not (data.get("status") == "UP" and data.get("auth") == derive_pin()), \
            "Service returns the /status success response for arbitrary paths"


def test_unlock_exp_exists():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} does not exist."


def test_expect_script_spawns_unlock_and_sends_pin():
    pin = derive_pin()
    backup = "/tmp/fw_unlock.verifier_backup"
    marker = "/tmp/verifier_unlock_spawned"
    received = "/tmp/verifier_pin_received"
    for path in (backup, marker, received, FLAG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.replace(UNLOCK, backup)
    wrapper = f'''#!/bin/sh
printf 'Please enter the emergency voice PIN: '
IFS= read -r supplied
printf '%s' "$supplied" > {received}
touch {marker}
if [ "$supplied" = "{pin}" ]; then
    printf 'Firewall unlocked.\\n'
    printf 'UNLOCKED\\n' > {FLAG}
    exit 0
fi
printf 'Invalid PIN.\\n'
exit 1
'''
    try:
        pathlib.Path(UNLOCK).write_text(wrapper)
        os.chmod(UNLOCK, 0o755)
        result = run_expect_script()
    finally:
        try:
            os.unlink(UNLOCK)
        except FileNotFoundError:
            pass
        os.replace(backup, UNLOCK)

    assert result.returncode == 0, f"Expect script failed against the required prompt:\n{result.stdout}"
    assert os.path.isfile(marker), "Expect script did not spawn /app/fw_unlock"
    assert pathlib.Path(received).read_text() == pin, "Expect script did not send the derived four-digit PIN"


def test_fw_unlocked_flag_created_by_real_program():
    try:
        os.unlink(FLAG)
    except FileNotFoundError:
        pass
    result = run_expect_script()
    assert result.returncode == 0, f"Expect script failed with the real fw_unlock program:\n{result.stdout}"
    assert os.path.isfile(FLAG), f"Firewall unlocked flag {FLAG} does not exist."
    assert pathlib.Path(FLAG).read_text().strip() == "UNLOCKED"


def test_monitor_service_c_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."


def test_monitor_service_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled executable"


def test_submitted_binary_serves_required_endpoint():
    proc, response = start_service(BINARY)
    try:
        assert_valid_status_response(response)
        assert_not_catchall_success()
    finally:
        kill_port_8080()
        if proc.poll() is None:
            proc.kill()


def test_c_source_builds_and_serves_required_endpoint():
    rebuilt = "/tmp/monitor_service_rebuilt"
    build = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=20, check=False,
    )
    assert build.returncode == 0, f"monitor_service.c did not compile:\n{build.stdout}"
    proc, response = start_service(rebuilt)
    try:
        assert_valid_status_response(response)
        assert_not_catchall_success()
    finally:
        kill_port_8080()
        if proc.poll() is None:
            proc.kill()


def test_monitor_service_remains_running():
    global RUNNING_SERVICE
    RUNNING_SERVICE, response = start_service(BINARY)
    assert_valid_status_response(response)
    assert RUNNING_SERVICE.poll() is None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
