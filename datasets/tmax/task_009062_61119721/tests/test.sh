#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import threading
import time

PROJECT = "/home/user/tcp_lb"
CONFIG = "/home/user/backends.txt"
LOG = "/home/user/diagnostics.log"
SUPERVISOR = "/home/user/supervisor.sh"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        local = fields[1]
                        if int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    if not inodes:
        return result
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
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def wait_for_listener(port, timeout=60, excluded=None):
    excluded = excluded or set()
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listening_pids(port) - excluded
        if pids:
            return next(iter(pids))
        time.sleep(0.1)
    return None


def kill_existing_listener(port):
    for pid in listening_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listening_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_pids(port), f"Could not clear pre-existing listener on port {port}"


def proc_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except FileNotFoundError:
        return []


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except FileNotFoundError:
        pass
    return 0


def ancestors(pid):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        yield pid
        pid = parent_pid(pid)


def assert_cargo_release_chain(listener_pid):
    cargo_pid = None
    for pid in ancestors(listener_pid):
        args = proc_args(pid)
        if args and os.path.basename(args[0]) == "cargo" and "run" in args and "--release" in args:
            cargo_pid = pid
            break
    assert cargo_pid is not None, "Listening proxy was not launched by `cargo run --release`"
    assert os.path.realpath(f"/proc/{cargo_pid}/cwd") == PROJECT, "cargo was not run from /home/user/tcp_lb"

    exe = os.path.realpath(f"/proc/{listener_pid}/exe")
    release_dir = os.path.realpath(os.path.join(PROJECT, "target", "release")) + os.sep
    assert exe.startswith(release_dir), f"Port 9000 listener is not the Cargo release artifact: {exe}"


class Backend:
    def __init__(self):
        self.token = secrets.token_hex(16)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]
        self.sock.listen(20)
        self.sock.settimeout(0.2)
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._accept, daemon=True)
        self.thread.start()

    @property
    def address(self):
        return f"127.0.0.1:{self.port}"

    def _accept(self):
        while not self.stopped.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        with conn:
            conn.settimeout(5)
            buf = b""
            while not self.stopped.is_set():
                try:
                    data = conn.recv(4096)
                except (socket.timeout, OSError):
                    return
                if not data:
                    return
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    response = self.token.encode() + b":" + line[::-1] + b"\n"
                    try:
                        conn.sendall(response)
                    except OSError:
                        return

    def close(self):
        self.stopped.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=1)


def reserve_down_port():
    guard = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    guard.bind(("127.0.0.1", 0))
    return guard, guard.getsockname()[1]


def write_config(addresses):
    temp = CONFIG + ".verifier.tmp"
    with open(temp, "w") as f:
        f.write("\n".join(addresses) + "\n")
    os.replace(temp, CONFIG)


def recv_line(sock):
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        assert chunk, "Proxy closed the connection before returning backend data"
        data += chunk
    line, remainder = data.split(b"\n", 1)
    assert not remainder, "Unexpected extra data returned by proxy"
    return line


def exercise_connection(expected_backend):
    with socket.create_connection(("127.0.0.1", 9000), timeout=3) as client:
        client.settimeout(3)
        for _ in range(2):
            payload = secrets.token_hex(24).encode()
            client.sendall(payload + b"\n")
            expected = expected_backend.token.encode() + b":" + payload[::-1]
            assert recv_line(client) == expected, "Data was not bidirectionally forwarded to the selected backend"


def test_final_state():
    assert os.path.isfile(SUPERVISOR), f"Supervisor script {SUPERVISOR} does not exist"
    assert os.access(SUPERVISOR, os.X_OK), f"Supervisor script {SUPERVISOR} is not executable"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Rust project Cargo.toml not found"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "Rust source file not found"

    kill_existing_listener(9000)
    backends = [Backend(), Backend(), Backend()]
    down_guard = None
    supervisor = None
    try:
        # Randomized backend addresses and per-run secrets prevent hardcoded replies.
        write_config([b.address for b in backends])
        open(LOG, "w").close()
        supervisor = subprocess.Popen(
            ["/bin/bash", SUPERVISOR],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )
        first_pid = wait_for_listener(9000, timeout=60)
        assert first_pid is not None, "Proxy did not start listening on port 9000 within 60 seconds"
        assert_cargo_release_chain(first_pid)

        # No readiness connection was made, so these must be strict A,B,C,A,B,C.
        expected_order = backends + backends
        for expected in expected_order:
            exercise_connection(expected)

        # Change startup configuration, kill the actual Rust listener, and require
        # the same supervisor to launch a new release artifact that rereads it.
        down_guard, down_port = reserve_down_port()
        down_address = f"127.0.0.1:{down_port}"
        write_config([backends[0].address, down_address, backends[2].address])
        open(LOG, "w").close()
        os.kill(first_pid, signal.SIGKILL)

        second_pid = wait_for_listener(9000, timeout=45, excluded={first_pid})
        assert second_pid is not None, "Supervisor did not restart the proxy after it exited"
        assert second_pid != first_pid, "Proxy process was not replaced after termination"
        assert supervisor.poll() is None, "Supervisor exited instead of supervising the proxy"
        assert_cargo_release_chain(second_pid)

        # First selection succeeds at A. Second selects the unavailable randomized
        # address and must fail over to the next backend while preserving traffic.
        exercise_connection(backends[0])
        exercise_connection(backends[2])

        deadline = time.time() + 3
        expected_log = f"FAIL: {down_address}"
        logs = ""
        while time.time() < deadline:
            with open(LOG) as f:
                logs = f.read()
            if expected_log in logs.splitlines():
                break
            time.sleep(0.05)
        assert expected_log in logs.splitlines(), f"Missing exact diagnostic line {expected_log!r}"
    finally:
        if supervisor is not None:
            try:
                os.killpg(supervisor.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                supervisor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(supervisor.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if down_guard is not None:
            down_guard.close()
        for backend in backends:
            backend.close()
        kill_existing_listener(9000)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
