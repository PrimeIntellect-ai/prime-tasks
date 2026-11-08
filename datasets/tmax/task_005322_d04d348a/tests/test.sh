#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import subprocess
import threading
import time

DEPLOY = "/home/user/deploy.sh"
MANIFEST = "/home/user/manifest.json"
PID_FILE = "/home/user/proxy.pid"
BINARY = "/home/user/lb-operator/target/release/lb-operator"
PAYLOAD_SIZE = 768 * 1024
PRELUDE_SIZE = 512 * 1024


class Backend:
    def __init__(self):
        self.marker = b"BACKEND_" + os.urandom(24)
        self.prelude = os.urandom(PRELUDE_SIZE)
        self.key = os.urandom(1)[0]
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(20)
        self.sock.settimeout(0.5)
        self.address = f"127.0.0.1:{self.sock.getsockname()[1]}"
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while not self.stopped.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn):
        try:
            conn.settimeout(15)
            # Send enough data to require simultaneous traffic in both directions.
            conn.sendall(self.marker + self.prelude)
            data = bytearray()
            while len(data) < PAYLOAD_SIZE:
                chunk = conn.recv(min(65536, PAYLOAD_SIZE - len(data)))
                if not chunk:
                    return
                data.extend(chunk)
            transformed = bytes(value ^ self.key for value in data)
            conn.sendall(transformed)
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def close(self):
        self.stopped.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self.thread.join(timeout=2)


def free_listen_address():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    address = f"127.0.0.1:{sock.getsockname()[1]}"
    sock.close()
    return address


def write_manifest(listen, backends):
    with open(MANIFEST, "w") as f:
        json.dump({"listen": listen, "backends": [b.address for b in backends]}, f)


def run_deploy():
    result = subprocess.run(
        ["su", "-", "user", "-c", "bash /home/user/deploy.sh"],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"deploy.sh failed. stdout: {result.stdout}\nstderr: {result.stderr}"


def read_pid():
    assert os.path.isfile(PID_FILE), f"{PID_FILE} does not exist after running deploy.sh."
    with open(PID_FILE) as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file does not contain a valid numeric PID, got: {value}"
    return int(value)


def assert_pid_is_release_binary(pid):
    proc_exe = f"/proc/{pid}/exe"
    assert os.path.exists(proc_exe), f"PID {pid} is not running."
    assert os.path.isfile(BINARY), "The release-mode Rust binary was not produced."
    assert os.path.samefile(proc_exe, BINARY), (
        f"PID {pid} is not the compiled Rust release artifact; it runs {os.readlink(proc_exe)}"
    )


def exercise_proxy(listen, backends):
    host, port_text = listen.rsplit(":", 1)
    payload = os.urandom(PAYLOAD_SIZE)
    last_error = None
    for _ in range(20):
        sock = None
        try:
            sock = socket.create_connection((host, int(port_text)), timeout=2)
            sock.settimeout(20)

            send_error = []
            def sender():
                try:
                    sock.sendall(payload)
                except Exception as exc:
                    send_error.append(exc)

            send_thread = threading.Thread(target=sender)
            send_thread.start()

            expected_prefix_len = len(backends[0].marker) + PRELUDE_SIZE
            received = bytearray()
            expected_total = expected_prefix_len + PAYLOAD_SIZE
            while len(received) < expected_total:
                chunk = sock.recv(min(65536, expected_total - len(received)))
                if not chunk:
                    break
                received.extend(chunk)

            send_thread.join(timeout=20)
            assert not send_thread.is_alive(), "Client-to-backend streaming blocked."
            assert not send_error, f"Sending through proxy failed: {send_error[0]}"

            response = bytes(received)
            assert b"BACKEND_" in response, f"Proxy did not return a backend response."
            selected = next((b for b in backends if response.startswith(b.marker)), None)
            assert selected is not None, "Response was not produced by any configured backend."
            prefix = selected.marker + selected.prelude
            expected = prefix + bytes(value ^ selected.key for value in payload)
            assert response == expected, (
                "Proxy did not preserve complete bidirectional TCP streams to the selected backend."
            )
            return
        except (ConnectionError, OSError, AssertionError) as exc:
            last_error = exc
            time.sleep(0.25)
        finally:
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass
    raise AssertionError(f"Proxy could not be exercised at manifest listen address: {last_error}")


def cleanup_proxy():
    if os.path.isfile(PID_FILE):
        try:
            with open(PID_FILE) as f:
                value = f.read().strip()
            if value.isdigit():
                subprocess.run(["kill", "-9", value], stderr=subprocess.DEVNULL)
        except OSError:
            pass


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY), f"{DEPLOY} is missing."
    assert os.access(DEPLOY, os.X_OK), f"{DEPLOY} is not executable."
    assert os.path.isfile("/home/user/lb-operator/src/main.rs"), "Rust main.rs is missing."


def test_proxy_functionality_manifest_and_idempotency():
    with open(MANIFEST, "rb") as f:
        original_manifest = f.read()

    first_backends = [Backend(), Backend()]
    second_backends = [Backend(), Backend()]
    listen = free_listen_address()

    try:
        # Force deploy.sh to produce the release executable rather than relying on
        # an already-present binary.
        for path in (BINARY, BINARY + ".d"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        write_manifest(listen, first_backends)
        run_deploy()
        time.sleep(0.5)
        pid1 = read_pid()
        assert_pid_is_release_binary(pid1)
        exercise_proxy(listen, first_backends)

        # Change every backend to unpredictable addresses. The restarted proxy
        # must reread manifest.json rather than serving a fixed response or using
        # hard-coded setup addresses.
        write_manifest(listen, second_backends)
        run_deploy()
        time.sleep(0.5)
        pid2 = read_pid()
        assert pid1 != pid2, "deploy.sh did not restart the process (PID is unchanged)."
        assert_pid_is_release_binary(pid2)
        exercise_proxy(listen, second_backends)
    finally:
        cleanup_proxy()
        for backend in first_backends + second_backends:
            backend.close()
        with open(MANIFEST, "wb") as f:
            f.write(original_manifest)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
