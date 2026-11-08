#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time


class Backend:
    def __init__(self, port, expected=None, response=None, greeting=None, echo=False):
        self.expected = expected
        self.response = response
        self.greeting = greeting
        self.echo = echo
        self.stop_event = threading.Event()
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", port))
        self.server.listen(1024)
        self.server.settimeout(0.1)
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def run(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.server.accept()
                threading.Thread(target=self.handle, args=(conn,), daemon=True).start()
            except socket.timeout:
                pass
            except OSError:
                break

    def handle(self, conn):
        try:
            conn.settimeout(2)
            if self.greeting is not None:
                conn.sendall(self.greeting)
            while True:
                data = conn.recv(65536)
                if not data:
                    break
                if self.echo:
                    conn.sendall(data)
                elif self.expected in data:
                    conn.sendall(self.response)
                    break
        except OSError:
            pass
        finally:
            conn.close()

    def close(self):
        self.stop_event.set()
        self.server.close()
        self.thread.join(timeout=2)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def fixed_request(target, payload, expected, timeout=2):
    with socket.create_connection(("127.0.0.1", 8080), timeout=timeout) as s:
        s.settimeout(timeout)
        s.sendall(("ROUTE " + target + "\n").encode() + payload)
        return expected in s.recv(4096)


def dynamic_request(target, greeting, payload):
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as s:
        s.settimeout(2)
        # Send the route independently so correct implementations need not rely on
        # the route and payload arriving in one particular packet.
        s.sendall(("ROUTE " + target + "\n").encode())
        got_greeting = b""
        while len(got_greeting) < len(greeting):
            part = s.recv(len(greeting) - len(got_greeting))
            if not part:
                break
            got_greeting += part
        assert got_greeting == greeting, (got_greeting, greeting)
        s.sendall(payload)
        s.shutdown(socket.SHUT_WR)
        echoed = b""
        while len(echoed) < len(payload):
            part = s.recv(65536)
            if not part:
                break
            echoed += part
        assert echoed == payload


def assert_immediate_close(line):
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as s:
        s.settimeout(0.75)
        s.sendall(line)
        try:
            data = s.recv(1)
            assert data == b"", "invalid route was not closed"
        except ConnectionResetError:
            pass
        except socket.timeout:
            raise AssertionError("invalid route was not closed immediately")


def test_reverse_proxy_pipeline():
    git_dir = "/home/user/lb_sync.git"
    proxy_bin = "/home/user/rust_proxy/target/release/rust_proxy"
    hook = os.path.join(git_dir, "hooks", "post-receive")
    reload_script = "/home/user/reload.exp"
    admin = "/app/lb_admin"

    assert os.path.isdir(git_dir), f"Bare Git repository not found at {git_dir}"
    bare = subprocess.run(["git", "--git-dir", git_dir, "rev-parse", "--is-bare-repository"], capture_output=True, text=True)
    assert bare.returncode == 0 and bare.stdout.strip() == "true", f"{git_dir} is not a bare Git repository"
    assert os.path.isfile(hook) and os.access(hook, os.X_OK), "Executable post-receive hook not found"
    assert os.path.isfile(reload_script), f"Expect script not found at {reload_script}"
    assert "/home/user/reload.exp" in open(hook, errors="replace").read(), "post-receive hook does not execute /home/user/reload.exp"
    assert os.path.isfile(proxy_bin), f"Rust proxy binary not found at {proxy_bin}. Did you run `cargo build --release`?"
    assert os.access(proxy_bin, os.X_OK), "Rust proxy binary is not executable"
    assert os.path.isfile("/home/user/rust_proxy/Cargo.toml"), "Rust project Cargo.toml is missing"
    assert os.path.isdir("/home/user/rust_proxy/src"), "Rust project src directory is missing"

    token = secrets.token_hex(8)
    target = "route_" + token
    unknown = "missing_" + token
    port_a = free_port()
    port_b = free_port()
    while port_b == port_a or port_b in (9001, 9002):
        port_b = free_port()
    while port_a in (9001, 9002):
        port_a = free_port()
    greeting_a = ("A:" + token + "\n").encode()
    greeting_b = ("B:" + token + "\n").encode()
    random_payload = os.urandom(131072)

    backends = [
        Backend(9001, b"HELLOTHERE", b"GENERALKENOBI"),
        Backend(9002, b"SECOND-" + token.encode(), b"SECOND-OK-" + token.encode()),
        Backend(port_a, greeting=greeting_a, echo=True),
        Backend(port_b, greeting=greeting_b, echo=True),
    ]
    proxy_proc = None
    workdir = None
    admin_saved = "/tmp/lb_admin_saved_" + token
    reload_saved = "/tmp/reload_saved_" + token
    admin_log = "/tmp/lb_admin_input_" + token
    reload_log = "/tmp/reload_invoked_" + token

    try:
        for backend in backends:
            backend.start()

        # Instrument the supplied CLI and expect script during verification. The
        # expect wrapper sources the submitted script, while proving that the hook
        # actually invoked /home/user/reload.exp. The CLI wrapper records the input
        # that the submitted expect program sends to the real proprietary binary.
        shutil.copy2(admin, admin_saved)
        shutil.copy2(reload_script, reload_saved)
        with open(admin, "w") as f:
            f.write("#!/bin/bash\n/usr/bin/tee -a " + admin_log + " | " + admin_saved + "\n")
        os.chmod(admin, 0o755)
        with open(reload_script, "w") as f:
            f.write("#!/usr/bin/expect -f\n")
            f.write("set fp [open \"" + reload_log + "\" a]\n")
            f.write("puts $fp \"invoked\"\nclose $fp\n")
            f.write("source \"" + reload_saved + "\"\n")
        os.chmod(reload_script, 0o755)

        config_dir = "/home/user/lb_config"
        os.makedirs(config_dir, exist_ok=True)
        flag_path = os.path.join(config_dir, "reload_flag")
        if os.path.exists(flag_path):
            os.unlink(flag_path)

        workdir = tempfile.mkdtemp()
        subprocess.run(["git", "init"], cwd=workdir, check=True, capture_output=True)
        subprocess.run(["git", "checkout", "-B", "master"], cwd=workdir, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=workdir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=workdir, check=True)

        routes_a = {"test1": 9001, "test2": 9002, target: port_a}
        with open(os.path.join(workdir, "routes.json"), "w") as f:
            json.dump(routes_a, f)
        subprocess.run(["git", "add", "routes.json"], cwd=workdir, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "initial routes"], cwd=workdir, check=True, capture_output=True)
        push_proc = subprocess.run(["git", "push", git_dir, "master"], cwd=workdir, capture_output=True)
        assert push_proc.returncode == 0, f"Git push failed. Stderr: {push_proc.stderr.decode()}"

        routes_path = "/home/user/lb_config/routes.json"
        assert os.path.isfile(routes_path), f"{routes_path} not found. The post-receive hook failed to checkout files."
        with open(routes_path) as f:
            assert json.load(f) == routes_a, "post-receive hook did not extract the pushed configuration"
        assert os.path.isfile(flag_path), f"{flag_path} not found. The expect script failed to run or reload the config."
        assert time.time() - os.path.getmtime(flag_path) < 15, "reload_flag was not recently modified"
        assert os.path.isfile(reload_log) and "invoked" in open(reload_log).read(), "post-receive did not run /home/user/reload.exp"
        transcript = open(admin_log, "rb").read()
        for command in (b"admin\n", b"secret123\n", b"reload config\n", b"quit\n"):
            assert command in transcript, f"expect script did not send {command!r} to /app/lb_admin"
        assert transcript.index(b"admin\n") < transcript.index(b"secret123\n") < transcript.index(b"reload config\n") < transcript.index(b"quit\n")

        proxy_proc = subprocess.Popen([proxy_bin], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
        assert proxy_proc.poll() is None, "Rust proxy exited instead of listening on 127.0.0.1:8080"

        # Preserve the original high-concurrency assertion.
        success_count = 0
        lock = threading.Lock()
        def send_original_request():
            nonlocal success_count
            try:
                if fixed_request("test1", b"HELLOTHERE", b"GENERALKENOBI"):
                    with lock:
                        success_count += 1
            except OSError:
                pass
        total_requests = 1000
        with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
            list(executor.map(lambda _: send_original_request(), range(total_requests)))
        success_rate = success_count / total_requests
        assert success_rate >= 0.95, f"Metric success_rate is {success_rate}, below 0.95"

        # Exercise a second fixed route and a randomized target, port, payload,
        # backend-to-client greeting, and large client-to-backend transfer.
        second_payload = b"SECOND-" + token.encode()
        assert fixed_request("test2", second_payload, b"SECOND-OK-" + token.encode())
        dynamic_request(target, greeting_a, random_payload)
        assert_immediate_close(("ROUTE " + unknown + "\n").encode())
        assert_immediate_close(("NOT_A_ROUTE " + target + "\n").encode())
        assert_immediate_close(b"ROUTE\n")

        # Changing routes.json alone must not invalidate the cache.
        routes_b = {"test1": 9001, "test2": 9002, target: port_b}
        with open(routes_path, "w") as f:
            json.dump(routes_b, f)
        time.sleep(0.2)
        dynamic_request(target, greeting_a, b"cached-" + os.urandom(8192))

        # A second pushed configuration must run the hook/expect/CLI pipeline and
        # cause the already-running proxy to reload based on reload_flag.
        time.sleep(1.1)
        with open(os.path.join(workdir, "routes.json"), "w") as f:
            json.dump(routes_b, f)
        subprocess.run(["git", "add", "routes.json"], cwd=workdir, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "reroute randomized target"], cwd=workdir, check=True, capture_output=True)
        push2 = subprocess.run(["git", "push", git_dir, "master"], cwd=workdir, capture_output=True)
        assert push2.returncode == 0, f"Second Git push failed: {push2.stderr.decode()}"
        assert open(reload_log).read().count("invoked") >= 2, "post-receive did not execute reload.exp on the second push"
        assert open(admin_log, "rb").read().count(b"reload config\n") >= 2, "reload.exp did not reload through lb_admin on the second push"

        deadline = time.time() + 6
        last_error = None
        while time.time() < deadline:
            try:
                dynamic_request(target, greeting_b, b"reloaded-" + os.urandom(16384))
                last_error = None
                break
            except (AssertionError, OSError) as exc:
                last_error = exc
                time.sleep(0.1)
        assert last_error is None, f"proxy did not reload routes after reload_flag changed: {last_error}"

    finally:
        if proxy_proc is not None:
            proxy_proc.terminate()
            try:
                proxy_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proxy_proc.kill()
        for backend in backends:
            backend.close()
        if os.path.exists(admin_saved):
            os.replace(admin_saved, admin)
        if os.path.exists(reload_saved):
            os.replace(reload_saved, reload_script)
        if workdir:
            shutil.rmtree(workdir, ignore_errors=True)
        for path in (admin_log, reload_log):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
