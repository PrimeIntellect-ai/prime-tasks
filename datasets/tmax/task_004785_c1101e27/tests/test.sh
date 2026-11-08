#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import pwd
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time

USER = pwd.getpwnam("user")
STARTED_PIDS = set()
BACKEND = None


def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_for_socket_inodes(inodes):
    found = set()
    if not inodes:
        return found
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
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def kill_listeners(port):
    for pid in pids_for_socket_inodes(listener_inodes(port)):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids_for_socket_inodes(listener_inodes(port)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def kill_old_user_processes():
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.stat(f"/proc/{pid}").st_uid != USER.pw_uid:
                continue
            with open(f"/proc/{pid}/comm") as f:
                comm = f.read().strip()
            if comm in ("ssh", "service"):
                os.kill(pid, signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.3)


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, PermissionError):
        return []


def process_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        return dict(x.decode(errors="replace").split("=", 1) for x in entries if b"=" in x)
    except (FileNotFoundError, PermissionError):
        return {}


def user_processes_for_executable(path):
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.stat(f"/proc/{pid}").st_uid != USER.pw_uid:
                continue
            if os.path.samefile(f"/proc/{pid}/exe", path):
                result.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    return result


def ensure_ssh_test_fixture():
    subprocess.run(["ssh-keygen", "-A"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod("/home/user", 0o755)
    os.chmod("/home/user/.ssh", 0o700)
    os.chmod("/home/user/.ssh/authorized_keys", 0o600)
    os.chown("/home/user/.ssh", USER.pw_uid, USER.pw_gid)
    os.chown("/home/user/.ssh/authorized_keys", USER.pw_uid, USER.pw_gid)
    # Make the setup's password-locked account usable with its authorized key.
    subprocess.run(["usermod", "-p", "NP", "user"], check=True)
    os.makedirs("/run/sshd", exist_ok=True)
    if not listener_inodes(22):
        subprocess.run(["/usr/sbin/sshd"], check=True)


def start_backend(nonce):
    ready = threading.Event()

    def serve():
        global BACKEND
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        BACKEND = srv
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", 9999))
        srv.listen(10)
        srv.settimeout(0.5)
        ready.set()
        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with conn:
                conn.sendall(nonce)

    threading.Thread(target=serve, daemon=True).start()
    assert ready.wait(3), "Could not start the verifier's challenge backend on port 9999."


def cleanup():
    if BACKEND is not None:
        try:
            BACKEND.close()
        except OSError:
            pass
    for pid in STARTED_PIDS:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


atexit.register(cleanup)


def test_00_artifacts_actually_work_together():
    binary = "/home/user/bin/service"
    script = "/home/user/run_service.sh"
    assert os.path.isfile(binary), "Compiled service is missing."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "service must be a compiled executable, not a script or dummy text file."

    os.makedirs("/home/user/data_spool", exist_ok=True)
    os.chown("/home/user/data_spool", USER.pw_uid, USER.pw_gid)

    # Exercise the compiled program on an unpredictable path and a non-UTC,
    # deterministic timezone. This checks getenv(), localtime()/strftime()
    # behavior rather than trusting source-code keywords or a prewritten log.
    probe = f"/home/user/data_spool/.verify-{secrets.token_hex(12)}.log"
    env = os.environ.copy()
    env.update({"HOME": "/home/user", "LOG_FILE_PATH": probe, "TZ": "JST-9"})
    proc = subprocess.Popen([binary], env=env, preexec_fn=demote_to_user,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 5
    while not os.path.isfile(probe) and time.time() < deadline:
        if proc.poll() is not None:
            break
        time.sleep(0.05)
    assert os.path.isfile(probe), "The compiled C program did not create the LOG_FILE_PATH file."
    with open(probe) as f:
        assert f.read() == "[INIT] Service started in timezone: JST\n"
    assert proc.poll() is None, "The service did not remain running after initialization."
    proc.terminate()
    proc.wait(timeout=3)
    os.unlink(probe)

    missing_env = os.environ.copy()
    missing_env.pop("LOG_FILE_PATH", None)
    missing_env["TZ"] = "UTC"
    result = subprocess.run([binary], env=missing_env, preexec_fn=demote_to_user,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            timeout=3)
    assert result.returncode == 1, "service must exit with code 1 when LOG_FILE_PATH is unset."

    # Remove fabricated/pre-existing state, then execute the submitted startup
    # script itself. A marker verifies that rerunning it preserves an existing
    # spool directory.
    kill_old_user_processes()
    kill_listeners(8888)
    kill_listeners(9999)
    log = "/home/user/data_spool/service.log"
    try:
        os.unlink(log)
    except FileNotFoundError:
        pass
    marker = "/home/user/data_spool/.idempotency-marker"
    with open(marker, "w") as f:
        f.write("keep")
    os.chown(marker, USER.pw_uid, USER.pw_gid)

    ensure_ssh_test_fixture()
    nonce = secrets.token_bytes(32)
    start_backend(nonce)

    run_env = os.environ.copy()
    run_env["HOME"] = "/home/user"
    for _ in range(2):
        completed = subprocess.run([script], env=run_env, preexec_fn=demote_to_user,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   timeout=20)
        assert completed.returncode == 0, (
            "run_service.sh failed when executed or re-executed: "
            + completed.stderr.decode(errors="replace"))
    assert os.path.isfile(marker), "The startup script is not idempotent for an existing spool directory."

    deadline = time.time() + 8
    while time.time() < deadline:
        if os.path.isfile(log) and listener_inodes(8888):
            break
        time.sleep(0.1)

    assert os.path.isfile(log), "Executing run_service.sh did not produce the service log."
    with open(log) as f:
        content = f.read()
    assert "[INIT] Service started in timezone: UTC" in content

    service_pids = user_processes_for_executable(binary)
    assert service_pids, "run_service.sh did not leave the compiled service running."
    STARTED_PIDS.update(service_pids)
    assert any(process_environ(pid).get("TZ") == "UTC" and
               process_environ(pid).get("LOG_FILE_PATH") == log
               for pid in service_pids), "The running service did not receive the required exported environment."

    owners = pids_for_socket_inodes(listener_inodes(8888))
    ssh_owners = []
    for pid in owners:
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            continue
        if exe == "ssh":
            ssh_owners.append(pid)
    assert ssh_owners, "Port 8888 is not owned by an ssh process."
    STARTED_PIDS.update(ssh_owners)

    valid_argv = False
    for pid in ssh_owners:
        joined = " ".join(process_cmdline(pid))
        if ("8888:127.0.0.1:9999" in joined and "-N" in joined and "-f" in joined
                and "StrictHostKeyChecking=no" in joined and "user@127.0.0.1" in joined):
            valid_argv = True
    assert valid_argv, "The listening SSH process does not have the required forwarding options."

    with socket.create_connection(("127.0.0.1", 8888), timeout=3) as conn:
        received = b""
        while len(received) < len(nonce):
            chunk = conn.recv(len(nonce) - len(received))
            if not chunk:
                break
            received += chunk
    assert received == nonce, "Port 8888 does not actually forward through SSH to 127.0.0.1:9999."


def test_bin_service_compiled():
    path = "/home/user/bin/service"
    assert os.path.isfile(path), f"Compiled binary {path} does not exist. Did you compile the C code?"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {path} is not executable."


def test_log_file_correct():
    path = "/home/user/data_spool/service.log"
    assert os.path.isfile(path), f"Log file {path} does not exist. Did the service run and write to the correct path?"
    with open(path, 'r') as f:
        content = f.read()
    expected_string = "[INIT] Service started in timezone: UTC"
    assert expected_string in content, f"Log file {path} does not contain the expected string. Found: {content}"


def test_port_8888_listening():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        result = s.connect_ex(('127.0.0.1', 8888))
        assert result == 0, "Port 8888 is not listening. The SSH tunnel might not be running or configured correctly."
    finally:
        s.close()


def test_run_service_sh_contents():
    path = "/home/user/run_service.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    assert "TZ=UTC" in content, "Script does not export TZ=UTC."
    assert "LOG_FILE_PATH=/home/user/data_spool/service.log" in content, "Script does not export LOG_FILE_PATH correctly."
    assert "ssh " in content and "8888:127.0.0.1:9999" in content, "Script does not contain the correct SSH port forwarding command."
    assert "-N" in content and "-f" in content, "SSH command must use -N and -f flags."
    assert "/home/user/bin/service" in content, "Script does not launch the compiled service."


def test_c_code_updated():
    path = "/home/user/src/service.c"
    assert os.path.isfile(path), f"C source file {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    assert "getenv" in content, "C code does not appear to use getenv() to read LOG_FILE_PATH."
    assert "/var/log/service.log" not in content, "C code still contains the hardcoded broken log path."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
