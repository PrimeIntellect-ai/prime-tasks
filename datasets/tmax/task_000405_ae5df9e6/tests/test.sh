#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import threading
import time

SOURCE = "/home/user/finops_health_check.cpp"
SCRIPT = "/home/user/deploy_finops.sh"
BINARY = "/home/user/finops_health_check"
CONFIG = "/home/user/services.conf"
LOG = "/home/user/cloud_health.log"


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def assert_exact_stdout(actual, expected):
    assert actual in (expected, expected + "\n"), \
        f"Expected stdout to be exactly {expected!r}, got {actual!r}"


class TCPServer:
    def __init__(self, port, capture=False):
        self.port = port
        self.capture = capture
        self.received = []
        self.stop_event = threading.Event()
        self.ready = threading.Event()
        self.sock = None
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()
        assert self.ready.wait(3), f"Listener on port {self.port} did not start"

    def _run(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock = s
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", self.port))
        s.listen(20)
        s.settimeout(0.15)
        self.ready.set()
        try:
            while not self.stop_event.is_set():
                try:
                    conn, _ = s.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                with conn:
                    if self.capture:
                        conn.settimeout(1)
                        try:
                            self.received.append(conn.recv(4096))
                        except OSError:
                            self.received.append(b"")
        finally:
            try:
                s.close()
            except OSError:
                pass

    def stop(self):
        self.stop_event.set()
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.thread.join(timeout=2)


def socket_owner_pids(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == target and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    owners.add(int(name))
        except OSError:
            pass
    return owners


def kill_pid(pid):
    if pid == os.getpid():
        return
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def clean_old_task_processes():
    # Remove pre-existing forwarding or monitoring processes so only the submitted
    # deployment script can create the state exercised below.
    for port in (8080, 8081):
        for pid in socket_owner_pids(port):
            kill_pid(pid)

    me = os.getpid()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="ignore")
        except OSError:
            continue
        if ("/home/user/deploy_finops.sh" in cmd or
                "/home/user/finops_health_check" in cmd or
                "/home/user/cloud_health.log" in cmd or
                ("socat" in cmd and "8080" in cmd)):
            kill_pid(pid)
    time.sleep(0.25)


def read_log():
    if not os.path.exists(LOG):
        return [], b""
    with open(LOG, "rb") as f:
        raw = f.read()
    lines = raw.splitlines()
    return [line.decode(errors="replace") for line in lines], raw


def wait_for_line_count(count, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        lines, raw = read_log()
        if len(lines) >= count and raw.endswith(b"\n"):
            return lines, time.monotonic()
        time.sleep(0.03)
    lines, _ = read_log()
    raise AssertionError(f"Timed out waiting for {count} health log lines; found {lines!r}")


def test_final_state():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} does not exist."
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    # Compile and exercise the C++ implementation on dynamically selected ports.
    compile_result = subprocess.run(
        ["g++", SOURCE, "-o", "/tmp/finops_test_bin"],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, \
        f"Failed to compile C++ code:\n{compile_result.stderr}"

    no_arg = subprocess.run(["/tmp/finops_test_bin"], capture_output=True, text=True, timeout=5)
    assert no_arg.returncode != 0, "C++ program must reject invocation without exactly one argument."
    two_args = subprocess.run(
        ["/tmp/finops_test_bin", "/tmp/a", "/tmp/b"],
        capture_output=True, text=True, timeout=5
    )
    assert two_args.returncode != 0, "C++ program must reject more than one argument."

    down_port = free_port()
    other_port = free_port()
    while other_port == down_port:
        other_port = free_port()
    conf_path = "/tmp/test_services_dynamic.conf"
    with open(conf_path, "w") as f:
        f.write(f"127.0.0.1:{down_port}\n127.0.0.1:{other_port}\n")

    result = subprocess.run(
        ["/tmp/finops_test_bin", conf_path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 1, "C++ program should exit with code 1 when an endpoint is down."
    assert_exact_stdout(result.stdout, f"DOWN_REASON: 127.0.0.1:{down_port}")

    up1_port = free_port()
    up2_port = free_port()
    while up2_port == up1_port:
        up2_port = free_port()
    up1 = TCPServer(up1_port)
    up2 = TCPServer(up2_port)
    up1.start()
    up2.start()
    try:
        with open(conf_path, "w") as f:
            f.write(f"127.0.0.1:{up1_port}\n127.0.0.1:{up2_port}\n")
        result = subprocess.run(
            ["/tmp/finops_test_bin", conf_path], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, "C++ program should exit with code 0 when all endpoints are up."
        assert_exact_stdout(result.stdout, "ALL_UP")
    finally:
        up1.stop()
        up2.stop()

    # Clear any state created manually before verification, then execute the
    # submitted deployment artifact itself.
    clean_old_task_processes()
    for path in (BINARY, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    service1_port = free_port()
    service2_port = free_port()
    while service2_port == service1_port:
        service2_port = free_port()
    service1 = TCPServer(service1_port)
    service2 = TCPServer(service2_port)
    backend = TCPServer(8081, capture=True)
    service1.start()
    service2.start()
    backend.start()

    before_pids = {int(x) for x in os.listdir("/proc") if x.isdigit()}
    try:
        with open(CONFIG, "w") as f:
            f.write(f"127.0.0.1:{service1_port}\n127.0.0.1:{service2_port}\n")

        proc = subprocess.Popen([SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            return_code = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise AssertionError("deploy_finops.sh blocked instead of returning after backgrounding its services.")
        assert return_code == 0, f"deploy_finops.sh exited with code {return_code}."

        assert os.path.isfile(BINARY), "Deployment script did not create /home/user/finops_health_check."
        assert os.access(BINARY, os.X_OK), "Compiled health checker is not executable."

        # Verify forwarding created by the executed script.
        deadline = time.monotonic() + 4
        last_error = None
        while time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.5) as sender:
                    sender.sendall(b"FINOPS_TEST")
                last_error = None
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)
        assert last_error is None, f"Failed to connect and send data to port 8080: {last_error}"

        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and b"FINOPS_TEST" not in backend.received:
            time.sleep(0.05)
        assert backend.received, "No data received on port 8081; socat forwarding is not working."
        assert b"FINOPS_TEST" in backend.received, \
            f"Data received on 8081 did not match data sent to 8080: {backend.received!r}"

        # With both configured services available, require exact PASS records at
        # approximately two-second intervals.
        lines, pass1_time = wait_for_line_count(1, 5)
        assert lines[0] == "CLOUD_HEALTH: PASS", f"Unexpected first log line: {lines[0]!r}"
        lines, pass2_time = wait_for_line_count(2, 4)
        assert lines[1] == "CLOUD_HEALTH: PASS", f"Unexpected second log line: {lines[1]!r}"
        pass_interval = pass2_time - pass1_time
        assert 1.3 <= pass_interval <= 3.2, \
            f"Health checks are not running every 2 seconds (observed {pass_interval:.2f}s)."

        # Make one configured endpoint fail. The same deployed monitor must append
        # exact FAIL records, again on the two-second cadence.
        service2.stop()
        lines, fail1_time = wait_for_line_count(3, 4)
        assert lines[2] == "CLOUD_HEALTH: FAIL", f"Expected exact FAIL line, got {lines[2]!r}"
        lines, fail2_time = wait_for_line_count(4, 4)
        assert lines[3] == "CLOUD_HEALTH: FAIL", f"Expected exact FAIL line, got {lines[3]!r}"
        fail_interval = fail2_time - fail1_time
        assert 1.3 <= fail_interval <= 3.2, \
            f"Health checks are not running every 2 seconds (observed {fail_interval:.2f}s)."

        final_lines, raw = read_log()
        assert raw.endswith(b"\n"), "Health log entries must be complete newline-terminated lines."
        assert all(line in ("CLOUD_HEALTH: PASS", "CLOUD_HEALTH: FAIL") for line in final_lines), \
            f"Health log contains non-exact entries: {final_lines!r}"
    finally:
        service1.stop()
        service2.stop()
        backend.stop()
        # Remove processes created by the deployment script so verification exits cleanly.
        for _ in range(3):
            current = {int(x) for x in os.listdir("/proc") if x.isdigit()}
            for pid in current - before_pids:
                if pid != os.getpid():
                    kill_pid(pid)
            for pid in socket_owner_pids(8080):
                kill_pid(pid)
            time.sleep(0.1)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
