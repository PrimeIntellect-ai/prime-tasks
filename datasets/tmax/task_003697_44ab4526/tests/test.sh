#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /run/sshd
/usr/sbin/sshd >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import signal
import socket
import subprocess
import time
import pytest

HOME = "/home/user"
DB_SCRIPT = "/home/user/bin/db-restore.sh"
APP_SCRIPT = "/home/user/bin/app-restore.sh"
DEPLOY_SCRIPT = "/home/user/deploy_restore_test.sh"


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def proc_state(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("State:"):
                return line.split()[1]
    return None


def proc_ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            text = f.read()
        return int(text[text.rfind(")") + 2:].split()[1])
    except (FileNotFoundError, ProcessLookupError, ValueError):
        return None


def all_pids():
    return [int(x) for x in os.listdir("/proc") if x.isdigit()]


def descendants(parent):
    result = set()
    changed = True
    while changed:
        changed = False
        for pid in all_pids():
            if pid not in result and proc_ppid(pid) in ({parent} | result):
                result.add(pid)
                changed = True
    return result


def tcp_listeners(port):
    found = []
    path = "/proc/net/tcp"
    try:
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                local, state, inode = fields[1], fields[3], fields[9]
                addr_hex, port_hex = local.split(":")
                if state == "0A" and int(port_hex, 16) == port:
                    address = socket.inet_ntoa(bytes.fromhex(addr_hex)[::-1])
                    found.append((address, inode))
    except FileNotFoundError:
        pass
    return found


def inode_owners(inode):
    owners = set()
    target = f"socket:[{inode}]"
    for pid in all_pids():
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        owners.add(pid)
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def listener_owners(port):
    result = []
    for address, inode in tcp_listeners(port):
        for pid in inode_owners(inode):
            result.append((address, pid))
    return result


def kill_previous_deployment():
    targets = set()
    for pid in all_pids():
        cmd = proc_cmdline(pid)
        joined = " ".join(cmd)
        if DB_SCRIPT in cmd or APP_SCRIPT in cmd:
            targets.add(pid)
        if os.path.basename(cmd[0]) == "ssh" if cmd else False:
            if "9091" in joined and "8081" in joined:
                targets.add(pid)
    for port in (8081, 9091):
        targets.update(pid for _, pid in listener_owners(port))
    expanded = set(targets)
    for pid in list(targets):
        expanded.update(descendants(pid))
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in expanded:
            try:
                os.kill(pid, sig)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.3)


def read_service_pids():
    with open(f"{HOME}/service.pids") as f:
        return [int(line.strip()) for line in f if line.strip()]


def wait_for(predicate, timeout=5.0, interval=0.05):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


@pytest.fixture(scope="session", autouse=True)
def execute_submission_from_clean_state():
    assert os.path.isfile(DEPLOY_SCRIPT), f"File {DEPLOY_SCRIPT} does not exist."
    kill_previous_deployment()

    for path in (
        f"{HOME}/restore_env.sh",
        f"{HOME}/service.pids",
        f"{HOME}/logrotate.conf",
        f"{HOME}/logrotate.state",
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.makedirs(f"{HOME}/logs", exist_ok=True)
    for name in os.listdir(f"{HOME}/logs"):
        path = os.path.join(f"{HOME}/logs", name)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)

    for name, size in (("db.log", 15 * 1024), ("app.log", 12 * 1024)):
        path = f"{HOME}/logs/{name}"
        with open(path, "wb") as f:
            f.write(b"\0" * size)
        os.chown(path, 1000, 1000)
        os.chmod(path, 0o666)

    started = time.time()
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", DEPLOY_SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    assert result.returncode == 0, "deploy_restore_test.sh did not execute successfully"
    assert wait_for(lambda: os.path.isfile(f"{HOME}/service.pids"), 2), "Deployment did not create service.pids"
    yield started


def test_deploy_script_exists():
    path = "/home/user/deploy_restore_test.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "#!/bin/" in content or "bash" in content, f"File {path} does not appear to be a valid bash script."


def test_restore_env_file():
    path = "/home/user/restore_env.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert re.search(r"export\s+DB_PORT=9091", content), "DB_PORT=9091 not exported correctly in restore_env.sh"
    assert re.search(r"export\s+RESTORE_ENV=testing", content), "RESTORE_ENV=testing not exported correctly in restore_env.sh"


def test_service_pids_file():
    path = "/home/user/service.pids"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 PIDs in {path}, found {len(lines)}"
    for pid in lines:
        assert pid.isdigit(), f"Found non-integer PID '{pid}' in {path}"

    db_pid, app_pid, ssh_pid = map(int, lines)
    for pid in (db_pid, app_pid, ssh_pid):
        assert os.path.isdir(f"/proc/{pid}"), f"PID {pid} is not running"
        assert proc_state(pid) != "Z", f"PID {pid} is a zombie"
        assert proc_uid(pid) == 1000, f"PID {pid} is not running as user"

    db_cmd = proc_cmdline(db_pid)
    app_cmd = proc_cmdline(app_pid)
    ssh_cmd = proc_cmdline(ssh_pid)
    assert len(db_cmd) == 2 and os.path.basename(db_cmd[0]) in ("bash", "sh") and db_cmd[1] == DB_SCRIPT, "First PID is not the db-restore.sh process"
    assert len(app_cmd) == 2 and os.path.basename(app_cmd[0]) in ("bash", "sh") and app_cmd[1] == APP_SCRIPT, "Second PID is not the app-restore.sh process"
    assert ssh_cmd and os.path.basename(os.path.realpath(f"/proc/{ssh_pid}/exe")) == "ssh", "Third PID is not an SSH client process"

    with open(f"/proc/{app_pid}/environ", "rb") as f:
        environment = set(f.read().split(b"\0"))
    assert b"DB_PORT=9091" in environment, "App process was not launched with DB_PORT=9091"
    assert b"RESTORE_ENV=testing" in environment, "App process was not launched with RESTORE_ENV=testing"


def test_logrotate_conf():
    path = "/home/user/logrotate.conf"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "size 10k" in content, "Missing 'size 10k' in logrotate.conf"
    assert "rotate 5" in content, "Missing 'rotate 5' in logrotate.conf"
    assert "compress" in content, "Missing 'compress' in logrotate.conf"
    assert "missingok" in content, "Missing 'missingok' in logrotate.conf"
    assert "/home/user/logs/*.log" in content or "/home/user/logs/" in content, "Target log path not found in logrotate.conf"


def test_logrotate_state(execute_submission_from_clean_state):
    path = "/home/user/logrotate.state"
    assert os.path.isfile(path), f"File {path} does not exist (logrotate might not have been executed with custom state file)."
    with open(path, "r") as f:
        content = f.read()
    assert "db.log" in content, "db.log not found in logrotate.state"
    assert "app.log" in content, "app.log not found in logrotate.state"
    assert content.startswith("logrotate state -- version"), "Custom state file is not a logrotate state file"
    assert os.path.getmtime(path) >= execute_submission_from_clean_state - 1, "logrotate.state was not produced by the verified execution"


def test_processes_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ps aux")

    assert "db-restore.sh" in output, "db-restore.sh process is not running."
    assert "app-restore.sh" in output, "app-restore.sh process is not running."
    assert "-L 9091:127.0.0.1:8081" in output or "-L 127.0.0.1:9091:127.0.0.1:8081" in output, "SSH tunnel process with correct port forwarding is not running."


def test_pid_owned_listeners_and_ssh_forward():
    db_pid, app_pid, ssh_pid = read_service_pids()
    ssh_text = " ".join(proc_cmdline(ssh_pid))
    assert re.search(r"(?:^|\s)-L\s+(?:127\.0\.0\.1:)?9091:127\.0\.0\.1:8081(?:\s|$)", ssh_text), "Saved SSH PID does not specify the required local forward"

    ssh_listener = wait_for(lambda: [(a, p) for a, p in listener_owners(9091) if p == ssh_pid], 5)
    assert ssh_listener, "The saved SSH PID does not own the port 9091 listener"
    assert all(address == "127.0.0.1" for address, _ in ssh_listener), "SSH forward is not bound to 127.0.0.1"

    db_family = {db_pid} | descendants(db_pid)
    db_listener = wait_for(lambda: [(a, p) for a, p in listener_owners(8081) if p in db_family], 5)
    assert db_listener, "The db-restore.sh process tree does not own the port 8081 listener"
    assert any(address == "127.0.0.1" or address == "0.0.0.0" for address, _ in db_listener)


def test_network_tunnel():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(('127.0.0.1', 9091))
    sock.close()
    assert result == 0, "Cannot connect to 127.0.0.1:9091. The SSH tunnel might not be working or db-restore.sh is not listening on 8081."

    db_pid, _, _ = read_service_pids()
    assert wait_for(lambda: any(pid in ({db_pid} | descendants(db_pid)) for _, pid in listener_owners(8081)), 4), "Database listener did not recover after a tunneled connection"


def test_app_process_actually_uses_configured_port():
    db_pid, app_pid, _ = read_service_pids()
    db_family = {db_pid} | descendants(db_pid)
    listener = wait_for(lambda: next((pid for _, pid in listener_owners(8081) if pid in db_family), None), 4)
    assert listener, "No database listener available for app connectivity test"
    os.kill(listener, signal.SIGSTOP)
    try:
        def app_nc_child():
            for pid in descendants(app_pid):
                cmd = proc_cmdline(pid)
                if cmd and os.path.basename(cmd[0]) in ("nc", "netcat", "nc.openbsd") and "127.0.0.1" in cmd and "9091" in cmd:
                    return pid
            return None
        assert wait_for(app_nc_child, 5, 0.005), "App process did not attempt to connect to DB_PORT 9091"
    finally:
        try:
            os.kill(listener, signal.SIGCONT)
        except ProcessLookupError:
            pass


def test_log_rotation_executed(execute_submission_from_clean_state):
    db_gz = "/home/user/logs/db.log.1.gz"
    app_gz = "/home/user/logs/app.log.1.gz"
    assert os.path.isfile(db_gz), f"Rotated log {db_gz} does not exist. Logrotate may not have run or compressed the files."
    assert os.path.isfile(app_gz), f"Rotated log {app_gz} does not exist. Logrotate may not have run or compressed the files."
    assert os.path.getmtime(db_gz) >= execute_submission_from_clean_state - 1
    assert os.path.getmtime(app_gz) >= execute_submission_from_clean_state - 1
    with gzip.open(db_gz, "rb") as f:
        assert f.read() == b"\0" * (15 * 1024), "db.log.1.gz is not the compressed seeded database log"
    with gzip.open(app_gz, "rb") as f:
        assert f.read() == b"\0" * (12 * 1024), "app.log.1.gz is not the compressed seeded application log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
