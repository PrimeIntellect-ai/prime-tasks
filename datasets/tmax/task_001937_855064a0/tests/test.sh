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
import math
import os
import socket
import subprocess
import time

import requests

WATCHDOG = "/home/user/watchdog.sh"
SOURCE = "/home/user/restore_svc/main.go"


def listening_pids(port):
    """Return PIDs owning a listening TCP socket on the requested port."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def service_pid():
    common = listening_pids(8080) & listening_pids(8081)
    assert len(common) == 1, f"Expected one process to listen on both ports, found {common}"
    return next(iter(common))


def watchdog_pids():
    found = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            exe = os.path.basename(os.readlink(f"/proc/{name}/exe"))
        except OSError:
            continue
        if exe in ("bash", "sh") and any(arg == WATCHDOG for arg in argv):
            found.add(int(name))
    return found


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            stat = f.read()
        return int(stat[stat.rfind(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def is_descendant(pid, ancestors):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        pid = parent_pid(pid)
    return pid in ancestors


def assert_go_process(pid):
    exe_path = f"/proc/{pid}/exe"
    result = subprocess.run(
        ["go", "version", "-m", exe_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Listening process is not a Go executable: {result.stdout}"
    assert "go1" in result.stdout, f"Go build information missing from service executable: {result.stdout}"


def check_http_and_tcp():
    url = "http://127.0.0.1:8080/api/v1/audio-meta"
    response = requests.get(url, headers={"Authorization": "Bearer operator-token-8831"}, timeout=2)
    assert response.status_code == 200
    with socket.create_connection(("127.0.0.1", 8081), timeout=2) as s:
        s.sendall(b"STATUS\n")
        assert s.recv(1024) == b"OK\n"
        assert s.recv(1024) == b""


def test_watchdog_script_exists_and_executable():
    """Test that the watchdog script exists and is executable."""
    script_path = "/home/user/watchdog.sh"
    assert os.path.exists(script_path), f"Watchdog script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Watchdog script {script_path} is not executable."


def test_log_file_exists():
    """Test that the restore service log file exists."""
    log_path = "/home/user/restore_service.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. The service might not be running or logging correctly."


def test_http_api_unauthorized():
    """Test that the HTTP API returns 401 when unauthorized."""
    url = "http://127.0.0.1:8080/api/v1/audio-meta"
    try:
        response = requests.get(url, timeout=2)
        assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"
    except requests.RequestException as e:
        assert False, f"HTTP request failed: {e}"


def test_http_api_authorized():
    """Test that the HTTP API returns the correct JSON when authorized."""
    url = "http://127.0.0.1:8080/api/v1/audio-meta"
    headers = {"Authorization": "Bearer operator-token-8831"}
    try:
        response = requests.get(url, headers=headers, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

        data = response.json()
        assert "filepath" in data, "Response JSON missing 'filepath'"
        assert data["filepath"] == "/app/voicemail_backup.wav", f"Expected filepath '/app/voicemail_backup.wav', got {data['filepath']}"

        assert "size_bytes" in data, "Response JSON missing 'size_bytes'"
        actual_size = os.path.getsize("/app/voicemail_backup.wav")
        assert data["size_bytes"] == actual_size, f"Expected size_bytes {actual_size}, got {data['size_bytes']}"

        assert "duration_seconds" in data, "Response JSON missing 'duration_seconds'"
        assert math.isclose(data["duration_seconds"], 12.45, abs_tol=0.15), f"Expected duration_seconds ~12.45, got {data['duration_seconds']}"
    except requests.RequestException as e:
        assert False, f"HTTP request failed: {e}"
    except ValueError:
        assert False, f"Failed to parse JSON response: {response.text}"


def test_tcp_health_check():
    """Test the TCP health check endpoint."""
    host = "127.0.0.1"
    port = 8081
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(b"STATUS\n")
            data = s.recv(1024)
            assert data == b"OK\n", f"Expected 'OK\\n', got {data!r}"
            extra_data = s.recv(1024)
            assert extra_data == b"", "Expected connection to be closed by server, but it remained open."
    except (socket.timeout, ConnectionRefusedError) as e:
        assert False, f"TCP connection failed: {e}"


def test_watchdog_running():
    """Test that watchdog.sh is currently running."""
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert "watchdog.sh" in output, "watchdog.sh does not appear to be running in the background."
    except subprocess.CalledProcessError:
        pass


def test_go_source_compiles_and_running_service_is_go():
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist"
    result = subprocess.run(
        ["go", "build", "-o", "/tmp/restore_svc_verifier_build", SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"main.go did not compile successfully: {result.stdout}"

    wpids = watchdog_pids()
    assert wpids, "No running Bash process executing /home/user/watchdog.sh was found"
    pid = service_pid()
    assert_go_process(pid)
    assert is_descendant(pid, wpids), "The Go service is not supervised by the running watchdog.sh process"


def test_service_restarts_within_two_seconds():
    old_pid = service_pid()
    wpids = watchdog_pids()
    assert wpids, "No running watchdog process found before restart test"
    assert_go_process(old_pid)
    assert is_descendant(old_pid, wpids), "Service is not a descendant of watchdog.sh"

    started = time.monotonic()
    os.kill(old_pid, 9)
    new_pid = None
    appeared_at = None
    while time.monotonic() - started <= 2.0:
        common = listening_pids(8080) & listening_pids(8081)
        common.discard(old_pid)
        if len(common) == 1:
            new_pid = next(iter(common))
            appeared_at = time.monotonic()
            break
        time.sleep(0.025)

    assert new_pid is not None, "watchdog.sh did not restart the service on both ports within 2 seconds"
    assert appeared_at - started <= 2.0, f"Service restart took {appeared_at - started:.3f} seconds"
    assert_go_process(new_pid)
    current_wpids = watchdog_pids()
    assert current_wpids, "watchdog.sh stopped during the restart test"
    assert is_descendant(new_pid, current_wpids), "Restarted Go service is not supervised by watchdog.sh"
    check_http_and_tcp()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
