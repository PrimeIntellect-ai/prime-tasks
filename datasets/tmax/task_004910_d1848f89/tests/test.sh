#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import socket
import subprocess
import threading
import time
import uuid

GATEWAY_PORT = 8111
APP_PORT = 8222
DATA_PORT = 8333
SCRIPT_PATH = "/home/user/check_connectivity.sh"
MONITOR_PATH = "/home/user/monitor.log"


def tcp_request(port, payload=b"PING\n", timeout=2.0):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(("127.0.0.1", port))
        s.sendall(payload)
        chunks = []
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
            if b"DATA_ACK" in b"".join(chunks):
                break
        return b"".join(chunks)


def test_routing_chain_success_rate():
    success_count = 0
    attempts = 3
    for _ in range(attempts):
        try:
            if b"DATA_ACK" in tcp_request(GATEWAY_PORT):
                success_count += 1
        except Exception:
            pass
        time.sleep(0.5)
    metric = success_count / attempts
    assert metric >= 1.0, f"Routing Chain Success Rate metric failed. Expected 1.0, got {metric}"


def test_check_connectivity_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), f"Script {SCRIPT_PATH} is not accessible."


def get_crontab(user=None):
    cmd = ["crontab", "-l"]
    if user is not None:
        cmd += ["-u", user]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        return ""


def test_cron_job_configured():
    crontab_output = get_crontab()
    if not crontab_output:
        crontab_output = get_crontab("user")
    assert "check_connectivity.sh" in crontab_output, "Cron job for check_connectivity.sh is not configured in crontab."


def listening_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def owners_of_inodes(inodes):
    owners = set()
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
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def process_argv(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]


def is_required_socat(pid, listen_port, target_port):
    try:
        argv = process_argv(pid)
    except OSError:
        return False
    if not argv or os.path.basename(argv[0]).lower() != "socat":
        return False
    upper = [x.upper() for x in argv[1:]]
    has_listener = any(re.search(rf"(?:TCP|TCP4|TCP6)-LISTEN:{listen_port}(?:,|$)", x) for x in upper)
    has_target = any(re.search(rf"(?:TCP|TCP4|TCP6)(?:-CONNECT)?:[^,]*:{target_port}(?:,|$)", x) for x in upper)
    return has_listener and has_target


def required_forwarder_pids(listen_port, target_port):
    owners = owners_of_inodes(listening_inodes(listen_port))
    return {pid for pid in owners if is_required_socat(pid, listen_port, target_port)}


def test_required_socat_forwarders_own_the_listeners():
    gateway = required_forwarder_pids(GATEWAY_PORT, APP_PORT)
    app = required_forwarder_pids(APP_PORT, DATA_PORT)
    assert gateway, "Port 8111 is not owned by a socat forwarder targeting port 8222"
    assert app, "Port 8222 is not owned by a socat forwarder targeting port 8333"
    assert listening_inodes(DATA_PORT), "No Data service is listening on port 8333"


def test_each_layer_reaches_data_service():
    for port in (DATA_PORT, APP_PORT, GATEWAY_PORT):
        response = tcp_request(port, b"LAYER_TEST\n")
        assert b"DATA_ACK" in response, f"Port {port} did not reach a service returning DATA_ACK"


def cron_daemon_pids():
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm") as f:
                if f.read().strip() in ("cron", "crond"):
                    pids.append(int(entry))
        except OSError:
            pass
    return pids


def run_fake_gateway(response):
    ready = threading.Event()
    result = {"payload": b"", "error": None}

    def serve():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                srv.bind(("127.0.0.1", GATEWAY_PORT))
                srv.listen(1)
                srv.settimeout(10)
                ready.set()
                conn, _ = srv.accept()
                with conn:
                    conn.settimeout(3)
                    try:
                        result["payload"] = conn.recv(4096)
                    except socket.timeout:
                        result["payload"] = b""
                    conn.sendall(response)
        except Exception as exc:
            result["error"] = exc
            ready.set()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    assert ready.wait(3), "Fake gateway did not start"
    assert result["error"] is None, f"Fake gateway failed: {result['error']}"
    return thread, result


def save_process(pid):
    st = os.stat(f"/proc/{pid}")
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = "/home/user"
    return process_argv(pid), st.st_uid, st.st_gid, cwd


def restart_process(spec):
    argv, uid, gid, cwd = spec
    def demote():
        os.setgid(gid)
        os.setuid(uid)
    return subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            preexec_fn=demote)


def monitor_contains_ok():
    try:
        with open(MONITOR_PATH, errors="replace") as f:
            return "STATUS: OK" in f.read()
    except FileNotFoundError:
        return False


def test_connectivity_script_checks_the_gateway_response():
    gateway_pids = required_forwarder_pids(GATEWAY_PORT, APP_PORT)
    assert gateway_pids, "Required gateway socat process disappeared"
    saved_gateway = [save_process(pid) for pid in gateway_pids]
    cron_pids = cron_daemon_pids()

    monitor_existed = os.path.lexists(MONITOR_PATH)
    monitor_data = b""
    monitor_mode = None
    monitor_uid = monitor_gid = None
    if monitor_existed:
        st = os.stat(MONITOR_PATH)
        monitor_mode, monitor_uid, monitor_gid = st.st_mode & 0o7777, st.st_uid, st.st_gid
        with open(MONITOR_PATH, "rb") as f:
            monitor_data = f.read()

    try:
        for pid in cron_pids:
            os.kill(pid, signal.SIGSTOP)
        for pid in gateway_pids:
            os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 5
        while listening_inodes(GATEWAY_PORT) and time.time() < deadline:
            time.sleep(0.1)
        assert not listening_inodes(GATEWAY_PORT), "Could not isolate GatewayPort to test the diagnostic script"

        user = pwd.getpwnam("user")
        with open(MONITOR_PATH, "wb"):
            pass
        os.chown(MONITOR_PATH, user.pw_uid, user.pw_gid)
        os.chmod(MONITOR_PATH, 0o666)

        thread, result = run_fake_gateway(b"NOPE\n")
        subprocess.run(["runuser", "-u", "user", "--", "/bin/bash", SCRIPT_PATH],
                       timeout=15, check=False)
        thread.join(3)
        assert result["error"] is None
        assert result["payload"], "Diagnostic script did not send a payload to GatewayPort"
        assert not monitor_contains_ok(), "Diagnostic script logged STATUS: OK without receiving DATA_ACK"

        thread, result = run_fake_gateway(b"DATA_ACK")
        subprocess.run(["runuser", "-u", "user", "--", "/bin/bash", SCRIPT_PATH],
                       timeout=15, check=False)
        thread.join(3)
        assert result["error"] is None
        assert result["payload"], "Diagnostic script did not send a payload to GatewayPort"
        assert monitor_contains_ok(), "Diagnostic script did not append STATUS: OK after receiving DATA_ACK"
    finally:
        if monitor_existed:
            with open(MONITOR_PATH, "wb") as f:
                f.write(monitor_data)
            os.chmod(MONITOR_PATH, monitor_mode)
            os.chown(MONITOR_PATH, monitor_uid, monitor_gid)
        else:
            try:
                os.unlink(MONITOR_PATH)
            except FileNotFoundError:
                pass
        if not listening_inodes(GATEWAY_PORT):
            for spec in saved_gateway:
                restart_process(spec)
        for pid in cron_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        deadline = time.time() + 5
        while not required_forwarder_pids(GATEWAY_PORT, APP_PORT) and time.time() < deadline:
            time.sleep(0.1)


def user_minutely_cron_lines():
    lines = []
    for raw in get_crontab("user").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"] and SCRIPT_PATH in fields[5]:
            lines.append(line)
    return lines


def test_user_cron_is_minutely_and_actually_executes():
    assert user_minutely_cron_lines(), "User crontab must run /home/user/check_connectivity.sh every minute"
    assert cron_daemon_pids(), "The cron daemon is not running"

    marker = f"/tmp/cron-verifier-{uuid.uuid4().hex}"
    with open(SCRIPT_PATH, "rb") as f:
        original = f.read()
    st = os.stat(SCRIPT_PATH)
    replacement = f"#!/bin/sh\nprintf '%s\\n' ran >> '{marker}'\n".encode()
    try:
        with open(SCRIPT_PATH, "wb") as f:
            f.write(replacement)
        os.chmod(SCRIPT_PATH, st.st_mode & 0o7777)
        os.chown(SCRIPT_PATH, st.st_uid, st.st_gid)

        deadline = time.time() + 75
        while time.time() < deadline:
            if os.path.exists(marker) and os.path.getsize(marker) > 0:
                break
            time.sleep(1)
        assert os.path.exists(marker) and os.path.getsize(marker) > 0, "The configured every-minute cron job did not execute"
    finally:
        with open(SCRIPT_PATH, "wb") as f:
            f.write(original)
        os.chmod(SCRIPT_PATH, st.st_mode & 0o7777)
        os.chown(SCRIPT_PATH, st.st_uid, st.st_gid)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
