#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time

BASE = "/home/user/migration"
SOURCE = BASE + "/backend.cpp"
SERVER = BASE + "/backend_server"
WATCHDOG = BASE + "/watchdog.sh"
SOCKET = BASE + "/run/app.sock"
CRONTAB = BASE + "/crontab.conf"


def exact_executable_pids(executable=SERVER):
    result = []
    target = os.path.realpath(executable)
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            linked = os.readlink(f"/proc/{name}/exe")
            if linked.endswith(" (deleted)"):
                linked = linked[:-10]
            if os.path.realpath(linked) == target:
                result.append(int(name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return sorted(result)


def stop_exact_processes(executable=SERVER):
    pids = exact_executable_pids(executable)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and exact_executable_pids(executable):
        time.sleep(0.05)
    for pid in exact_executable_pids(executable):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def socket_inode_for_path(path=SOCKET):
    try:
        with open("/proc/net/unix") as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[7] == path:
                    return fields[6]
    except FileNotFoundError:
        pass
    return None


def pid_owns_socket(pid, inode):
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                if os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{inode}]":
                    return True
            except OSError:
                pass
    except (FileNotFoundError, PermissionError):
        pass
    return False


def wait_for_service(executable=SERVER, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        pids = exact_executable_pids(executable)
        inode = socket_inode_for_path()
        if pids and inode and any(pid_owns_socket(pid, inode) for pid in pids):
            try:
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                client.settimeout(0.5)
                client.connect(SOCKET)
                client.close()
                return pids
            except OSError as exc:
                last_error = exc
        time.sleep(0.05)
    raise AssertionError(f"backend did not own and accept connections on {SOCKET}: {last_error}")


def remove_socket_path():
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass


def make_stale_socket():
    os.makedirs(os.path.dirname(SOCKET), exist_ok=True)
    remove_socket_path()
    stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    stale.bind(SOCKET)
    stale.close()
    assert stat.S_ISSOCK(os.stat(SOCKET).st_mode)


def test_socket_exists_and_is_socket():
    assert os.path.exists(SOCKET), f"Verification failed: {SOCKET} is missing."
    assert stat.S_ISSOCK(os.stat(SOCKET).st_mode), f"Verification failed: {SOCKET} is not a socket."


def test_backend_server_running():
    output = subprocess.check_output(["pgrep", "-f", SERVER], text=True)
    assert output.strip(), "Verification failed: backend_server process is not running."
    pids = wait_for_service()
    assert pids, "Verification failed: the submitted executable does not own the listening socket."


def test_crontab_conf_correct():
    assert os.path.isfile(CRONTAB), f"Verification failed: {CRONTAB} is missing."
    with open(CRONTAB) as f:
        content = f.read()
    lines = content.splitlines()
    assert len(lines) == 1, "Verification failed: crontab.conf must contain exactly one line."
    pattern = r"^[ \t]*\*[ \t]+\*[ \t]+\*[ \t]+\*[ \t]+\*[ \t]+/home/user/migration/watchdog\.sh[ \t]*$"
    assert re.fullmatch(pattern, lines[0]), "Verification failed: the sole cron line is not the required every-minute watchdog entry."


def test_watchdog_script_executable():
    assert os.path.isfile(WATCHDOG), f"Verification failed: {WATCHDOG} does not exist."
    assert os.access(WATCHDOG, os.X_OK), f"Verification failed: {WATCHDOG} is not executable."
    subprocess.run(["bash", "-n", WATCHDOG], check=True, timeout=5)


def test_backend_server_executable():
    assert os.path.isfile(SERVER), f"Verification failed: {SERVER} does not exist."
    assert os.access(SERVER, os.X_OK), f"Verification failed: {SERVER} is not executable."
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Verification failed: backend_server is not a compiled native executable."


def test_updated_source_compiles_and_listens_on_required_path():
    assert os.path.isfile(SOURCE), f"Verification failed: {SOURCE} is missing."
    with open(SOURCE, errors="replace") as f:
        source_text = f.read()
    assert SOCKET in source_text, "Verification failed: backend.cpp does not contain the required socket path."

    stop_exact_processes()
    remove_socket_path()
    with tempfile.TemporaryDirectory() as td:
        compiled = os.path.join(td, "compiled_backend")
        subprocess.run(["g++", SOURCE, "-o", compiled], check=True, timeout=30)
        process = subprocess.Popen([compiled])
        try:
            wait_for_service(compiled)
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
            remove_socket_path()


def test_watchdog_restart_stale_cleanup_and_no_duplicate_start():
    stop_exact_processes()
    remove_socket_path()

    backup = SERVER + ".verifier-backup"
    marker = "/tmp/watchdog_stub_marker"
    pidfile = "/tmp/watchdog_stub_pid"
    for path in (backup, marker, pidfile):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.rename(SERVER, backup)
    stub_pid = None
    try:
        with open(SERVER, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"echo $$ > {pidfile}\n")
            f.write(f"if [[ ! -e {SOCKET} ]]; then echo started >> {marker}; fi\n")
            f.write("while true; do sleep 1; done\n")
        os.chmod(SERVER, 0o755)
        make_stale_socket()
        subprocess.run([WATCHDOG], check=True, timeout=5)

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(marker):
            time.sleep(0.05)
        assert os.path.exists(marker), "Verification failed: watchdog did not remove the stale socket before starting backend_server."
        with open(pidfile) as f:
            stub_pid = int(f.read().strip())

        subprocess.run([WATCHDOG], check=True, timeout=5)
        time.sleep(0.4)
        with open(marker) as f:
            starts = [line for line in f.read().splitlines() if line == "started"]
        assert len(starts) == 1, "Verification failed: watchdog starts another backend_server while one is already running."
    finally:
        if stub_pid is None and os.path.exists(pidfile):
            try:
                with open(pidfile) as f:
                    stub_pid = int(f.read().strip())
            except (OSError, ValueError):
                pass
        if stub_pid:
            subprocess.run(["pkill", "-TERM", "-P", str(stub_pid)], check=False)
            try:
                os.kill(stub_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            os.unlink(SERVER)
        except FileNotFoundError:
            pass
        if os.path.exists(backup):
            os.rename(backup, SERVER)
        remove_socket_path()

    make_stale_socket()
    subprocess.run([WATCHDOG], check=True, timeout=5)
    first_pids = wait_for_service()
    subprocess.run([WATCHDOG], check=True, timeout=5)
    time.sleep(0.4)
    second_pids = wait_for_service()
    assert second_pids == first_pids, "Verification failed: watchdog duplicated or replaced a healthy backend_server."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
