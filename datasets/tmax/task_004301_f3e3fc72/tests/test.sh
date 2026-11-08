#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import subprocess
import time

EXPECTED = b'{"status": "healthy", "component": "backend"}'
MANAGER = "/home/user/appstack/manager.sh"
BACKEND = "/home/user/appstack/backend.py"
PROXY = "/home/user/appstack/proxy.py"
BACKEND_PID_FILE = "/home/user/appstack/run/backend.pid"
PROXY_PID_FILE = "/home/user/appstack/run/proxy.pid"


def is_running(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


def proc_cmdline(pid):
    try:
        with open(f"/proc/{int(pid)}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except (OSError, ValueError):
        return []


def proc_environ(pid):
    try:
        with open(f"/proc/{int(pid)}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        return {
            item.split(b"=", 1)[0].decode(errors="replace"):
            item.split(b"=", 1)[1].decode(errors="replace")
            for item in entries if b"=" in item
        }
    except (OSError, ValueError):
        return {}


def request(url):
    return subprocess.run(
        ["curl", "-sS", "--fail", "--max-time", "5", url],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def wait_for_request(url, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return request(url)
        except subprocess.CalledProcessError as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Request to {url} failed: {last_error.stderr.decode(errors='replace') if last_error else 'timeout'}")


def find_socat_forwarders():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
        except OSError:
            continue
        if os.path.basename(exe) != "socat":
            continue
        args = [arg.lower() for arg in proc_cmdline(name)]
        has_listener = any("listen" in arg and ":9090" in arg for arg in args)
        has_target = any("127.0.0.1:8080" in arg for arg in args)
        if has_listener and has_target:
            found.append(int(name))
    return found


def listening_socket_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    try:
                        local_port = int(local_address.rsplit(":", 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if local_port == port and state == "0A":
                        result.add(fields[9])
        except OSError:
            pass
    return result


def pid_owns_socket(pid, inodes):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return True
    except OSError:
        return False
    return False


def terminate_existing_services():
    targets = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        args = proc_cmdline(name)
        if BACKEND in args or PROXY in args:
            targets.append(int(name))
    for pid in targets:
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(is_running(pid) for pid in targets):
        time.sleep(0.1)
    for pid in targets:
        if is_running(pid):
            try:
                os.kill(pid, 9)
            except OSError:
                pass


def test_backup_created():
    backup_path = "/home/user/backups/config.json.bak"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."
    with open(backup_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Backup file {backup_path} is not valid JSON."
    assert config.get("upstream_socket") == "/tmp/wrong_app.sock", \
        "Backup file does not contain the original 'upstream_socket' value."


def test_bash_profile_updated():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"Profile file {profile_path} is missing."
    with open(profile_path, "r") as f:
        content = f.read()
    expected_line = "export APP_SOCKET_PATH=/home/user/appstack/run/app.sock"
    assert expected_line in content, \
        f"{profile_path} does not contain the expected export statement."


def test_config_updated():
    config_path = "/home/user/appstack/config.json"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."
    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Config file {config_path} is not valid JSON."
    assert config.get("upstream_socket") == "/home/user/appstack/run/app.sock", \
        "config.json 'upstream_socket' was not updated to the correct path."


def test_final_output_log_and_live_forwarding():
    log_path = "/home/user/final_output.log"
    assert os.path.isfile(log_path), f"Final output log {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()
    expected_output = '{"status": "healthy", "component": "backend"}'
    assert content == expected_output, \
        f"Output log content is incorrect. Expected '{expected_output}', got '{content}'."

    forwarders = find_socat_forwarders()
    assert forwarders, "No real socat process configured to forward port 9090 to 127.0.0.1:8080 is running."
    listener_inodes = listening_socket_inodes(9090)
    assert listener_inodes, "Nothing is listening on TCP port 9090."
    assert any(pid_owns_socket(pid, listener_inodes) for pid in forwarders), \
        "The socat forwarder does not own the listening socket on port 9090."

    live_output = request("http://127.0.0.1:9090/status")
    assert live_output == EXPECTED, f"Live request through port 9090 returned {live_output!r}."
    with open(log_path, "rb") as f:
        saved_output = f.read()
    assert saved_output == live_output, \
        "final_output.log is not the exact, unmodified output returned through the live port forward."


def test_manager_script_lifecycle():
    assert os.path.isfile(MANAGER), f"Manager script {MANAGER} is missing."
    st = os.stat(MANAGER)
    assert bool(st.st_mode & stat.S_IXUSR), f"Manager script {MANAGER} is not executable."

    # Clear only stack service state; leave the required socat forwarder running.
    subprocess.run(["/bin/bash", MANAGER, "stop"], cwd="/home/user/appstack", timeout=10,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    terminate_existing_services()
    for path in (BACKEND_PID_FILE, PROXY_PID_FILE):
        if os.path.exists(path):
            os.remove(path)

    started = subprocess.run(["/bin/bash", MANAGER, "start"], cwd="/home/user/appstack", timeout=10)
    assert started.returncode == 0, "manager.sh start returned a failure status."
    time.sleep(1)

    assert os.path.isfile(BACKEND_PID_FILE), f"Backend PID file {BACKEND_PID_FILE} was not created after start."
    assert os.path.isfile(PROXY_PID_FILE), f"Proxy PID file {PROXY_PID_FILE} was not created after start."

    with open(BACKEND_PID_FILE, "r") as f:
        backend_pid = f.read().strip()
    with open(PROXY_PID_FILE, "r") as f:
        proxy_pid = f.read().strip()

    assert backend_pid.isdigit(), "Backend PID file does not contain a valid PID."
    assert proxy_pid.isdigit(), "Proxy PID file does not contain a valid PID."
    assert backend_pid != proxy_pid, "Backend and proxy PID files contain the same PID."
    assert is_running(backend_pid), "Backend process is not running."
    assert is_running(proxy_pid), "Proxy process is not running."

    assert BACKEND in proc_cmdline(backend_pid), \
        "Backend PID does not refer to /home/user/appstack/backend.py."
    assert PROXY in proc_cmdline(proxy_pid), \
        "Proxy PID does not refer to /home/user/appstack/proxy.py."
    assert proc_environ(backend_pid).get("APP_SOCKET_PATH") == "/home/user/appstack/run/app.sock", \
        "backend.py was not started with the required APP_SOCKET_PATH environment variable."

    direct_output = wait_for_request("http://127.0.0.1:8080/status")
    assert direct_output == EXPECTED, f"The manager-started stack returned {direct_output!r} on port 8080."
    forwarded_output = wait_for_request("http://127.0.0.1:9090/status")
    assert forwarded_output == EXPECTED, f"The port 9090 forward returned {forwarded_output!r} after restart."

    stopped = subprocess.run(["/bin/bash", MANAGER, "stop"], cwd="/home/user/appstack", timeout=10)
    assert stopped.returncode == 0, "manager.sh stop returned a failure status."
    time.sleep(2)

    assert not os.path.isfile(BACKEND_PID_FILE), "Backend PID file was not removed after stop."
    assert not os.path.isfile(PROXY_PID_FILE), "Proxy PID file was not removed after stop."
    assert not is_running(backend_pid), "Backend process was not terminated."
    assert not is_running(proxy_pid), "Proxy process was not terminated."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
