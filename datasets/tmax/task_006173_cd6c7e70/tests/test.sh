#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import stat
import subprocess
import time

BACKEND_LINK = "/home/user/deploy/bin/backend_app"
PROXY_LINK = "/home/user/deploy/bin/proxy_app"
BACKEND_TARGET = "/home/user/migration/src/backend_app"
PROXY_TARGET = "/home/user/migration/src/proxy_app"
BACKEND_PIDFILE = "/home/user/deploy/run/backend.pid"
PROXY_PIDFILE = "/home/user/deploy/run/proxy.pid"
BACKEND_LOG = "/home/user/deploy/logs/backend.log"
PROXY_LOG = "/home/user/deploy/logs/proxy.log"
MANAGE = "/home/user/deploy/manage.sh"


def read_pid(path):
    assert os.path.isfile(path), f"PID file {path} does not exist."
    value = open(path).read().strip()
    assert value.isdigit() and int(value) > 1, f"Invalid PID in {path}: {value!r}"
    return int(value)


def process_is_live(pid):
    try:
        state = open(f"/proc/{pid}/stat").read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError):
        return False


def process_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            result.add(target[8:-1])
    return result


def listening_inodes_for_port(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local_port = int(fields[1].split(":")[1], 16)
                state_code = fields[3]
                if local_port == port and state_code == "0A":
                    result.add(fields[9])
    return result


def assert_service(pidfile, executable, argv, port, logfile):
    pid = read_pid(pidfile)
    assert process_is_live(pid), f"PID {pid} from {pidfile} is not a live process."

    actual_exe = os.path.realpath(f"/proc/{pid}/exe")
    assert actual_exe == executable, f"PID {pid} runs {actual_exe}, not {executable}."

    cmdline = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    cmdline = [part.decode(errors="replace") for part in cmdline if part]
    assert cmdline == argv, f"PID {pid} has command line {cmdline}, expected {argv}."

    owned = process_socket_inodes(pid)
    listeners = listening_inodes_for_port(port)
    assert owned & listeners, f"PID {pid} is not listening on TCP port {port}."

    for fd in (1, 2):
        destination = os.path.realpath(f"/proc/{pid}/fd/{fd}")
        assert destination == logfile, f"PID {pid} fd {fd} is redirected to {destination}, not {logfile}."
    return pid


def wait_for_services(timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            backend_pid = assert_service(
                BACKEND_PIDFILE, BACKEND_TARGET,
                [BACKEND_LINK, "8443"], 8443, BACKEND_LOG)
            proxy_pid = assert_service(
                PROXY_PIDFILE, PROXY_TARGET,
                [PROXY_LINK, "8080", "8443"], 8080, PROXY_LOG)
            return backend_pid, proxy_pid
        except (AssertionError, FileNotFoundError, ProcessLookupError, OSError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Services did not become ready: {last_error}")


def wait_stopped(pids, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if all(not process_is_live(pid) for pid in pids):
            return
        time.sleep(0.1)
    assert all(not process_is_live(pid) for pid in pids), f"Processes are still live: {pids}"


def assert_expected_logs():
    assert os.path.isfile(BACKEND_LOG), "backend.log was not created."
    assert os.path.isfile(PROXY_LOG), "proxy.log was not created."
    assert "Backend listening on 8443" in open(BACKEND_LOG).read(), "Backend output was not redirected to backend.log."
    assert "Proxy listening on 8080 forwarding to 8443" in open(PROXY_LOG).read(), "Proxy output was not redirected to proxy.log."


def test_backend_port_extracted():
    path = "/home/user/deploy/backend_port.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "8443", f"Expected backend_port.txt to contain '8443', but got '{content}'."


def test_symlinks_exist_and_targets_are_executables():
    assert os.path.islink(BACKEND_LINK), f"{BACKEND_LINK} is not a symlink."
    assert os.path.islink(PROXY_LINK), f"{PROXY_LINK} is not a symlink."

    backend_target = os.path.realpath(BACKEND_LINK)
    proxy_target = os.path.realpath(PROXY_LINK)
    assert backend_target == BACKEND_TARGET, f"Backend symlink points to {backend_target} instead of {BACKEND_TARGET}."
    assert proxy_target == PROXY_TARGET, f"Proxy symlink points to {proxy_target} instead of {PROXY_TARGET}."

    for target in (BACKEND_TARGET, PROXY_TARGET):
        assert os.path.isfile(target), f"Compiled executable {target} does not exist."
        mode = os.stat(target).st_mode
        assert stat.S_ISREG(mode), f"{target} is not a regular file."
        assert os.access(target, os.X_OK), f"{target} is not executable."
        with open(target, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{target} is not a compiled ELF executable."


def test_acls_set_correctly():
    path = "/home/user/deploy/logs/"
    assert os.path.isdir(path), f"Directory {path} does not exist."

    result = subprocess.run(["getfacl", path], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run getfacl."
    output = result.stdout
    assert "group:users:r-x" in output, "ACL group:users:r-x not found on logs directory."
    assert "default:group:users:r--" in output, "Default ACL default:group:users:r-- not found on logs directory."

    inherited = os.path.join(path, ".acl_inheritance_test")
    with open(inherited, "w") as f:
        f.write("test")
    try:
        file_acl = subprocess.run(["getfacl", inherited], capture_output=True, text=True, check=True).stdout
        assert "group:users:r--" in file_acl, "A newly created log file did not inherit users-group read permission."
    finally:
        os.unlink(inherited)


def test_processes_running():
    backend_running = False
    proxy_running = False
    ps_result = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True)
    for line in ps_result.stdout.splitlines():
        if "backend_app" in line and "8443" in line and "manage.sh" not in line and "grep" not in line:
            backend_running = True
        if "proxy_app" in line and "8080" in line and "8443" in line and "manage.sh" not in line and "grep" not in line:
            proxy_running = True
    assert backend_running, "backend_app is not running with argument 8443."
    assert proxy_running, "proxy_app is not running with arguments 8080 8443."

    wait_for_services()
    assert_expected_logs()


def test_manage_script_stop_start_and_argument_enforcement():
    assert os.path.isfile(MANAGE), f"Script {MANAGE} does not exist."
    assert os.access(MANAGE, os.X_OK), f"Script {MANAGE} is not executable."

    old_pids = (read_pid(BACKEND_PIDFILE), read_pid(PROXY_PIDFILE))
    stopped = subprocess.run([MANAGE, "stop"], check=False)
    assert stopped.returncode == 0, "manage.sh stop failed."
    wait_stopped(old_pids)
    time.sleep(0.2)

    backend_running = False
    proxy_running = False
    ps_result = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True)
    for line in ps_result.stdout.splitlines():
        if "backend_app" in line and "8443" in line and "manage.sh" not in line and "grep" not in line:
            backend_running = True
        if "proxy_app" in line and "8080" in line and "8443" in line and "manage.sh" not in line and "grep" not in line:
            proxy_running = True
    assert not backend_running, "backend_app is still running after manage.sh stop."
    assert not proxy_running, "proxy_app is still running after manage.sh stop."
    assert not os.path.exists(BACKEND_PIDFILE), "backend.pid was not deleted."
    assert not os.path.exists(PROXY_PIDFILE), "proxy.pid was not deleted."
    assert not listening_inodes_for_port(8443), "TCP port 8443 is still listening after stop."
    assert not listening_inodes_for_port(8080), "TCP port 8080 is still listening after stop."

    assert subprocess.run([MANAGE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0, "manage.sh accepted zero arguments."
    assert subprocess.run([MANAGE, "invalid"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0, "manage.sh accepted an invalid action."
    assert subprocess.run([MANAGE, "start", "extra"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0, "manage.sh accepted more than one argument."
    assert not os.path.exists(BACKEND_PIDFILE) and not os.path.exists(PROXY_PIDFILE), "Invalid invocations created PID files."
    assert not listening_inodes_for_port(8443) and not listening_inodes_for_port(8080), "Invalid invocations launched services."

    backend_bad = subprocess.run([BACKEND_TARGET], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    proxy_bad = subprocess.run([PROXY_TARGET, "8080"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    assert backend_bad.returncode != 0, "backend_app did not enforce its required argument count."
    assert proxy_bad.returncode != 0, "proxy_app did not enforce its required argument count."

    for log in (BACKEND_LOG, PROXY_LOG):
        if os.path.exists(log):
            os.unlink(log)

    started = subprocess.run([MANAGE, "start"], check=False, timeout=5)
    assert started.returncode == 0, "manage.sh start failed."
    new_pids = wait_for_services()
    assert new_pids[0] != new_pids[1], "Backend and proxy PID files contain the same PID."
    assert_expected_logs()

    for log in (BACKEND_LOG, PROXY_LOG):
        acl = subprocess.run(["getfacl", log], capture_output=True, text=True, check=True).stdout
        assert "group:users:r--" in acl, f"{log} did not inherit the users-group read ACL."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
