#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_build_broker.py
import asyncio
import json
import os
import queue
import secrets
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request

PROJECT = "/home/user/build_broker"
BASE_URL = "http://127.0.0.1:8080/api/build"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def post(target, body, timeout=3):
    req = urllib.request.Request(
        f"{BASE_URL}/{target}",
        data=body.encode("utf-8"),
        method="POST",
        headers={"Content-Type": "text/plain"},
    )
    try:
        with opener.open(req, timeout=timeout) as response:
            return response.getcode()
    except urllib.error.HTTPError as error:
        return error.code


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listening_inodes(port)
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
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def kill_port(port):
    pids = listener_pids(port)
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    assert not listener_pids(port), f"Could not free port {port}"


def wait_for_existing_server():
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            if post("java", "CMD javac\nRUN", timeout=0.5) == 400:
                return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.1)
    raise AssertionError("The submitted server was not running on 127.0.0.1:8080")


def main():
    assert os.path.isdir(PROJECT), "The build_broker directory does not exist"
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing"

    # Preserve the original final-state requirement that the agent left a working server running.
    wait_for_existing_server()

    metadata_run = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_run.returncode == 0, metadata_run.stderr
    metadata = json.loads(metadata_run.stdout)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == os.path.realpath(manifest)]
    assert len(packages) == 1, "Cargo metadata did not identify the submitted package"
    assert packages[0]["name"] == "build_broker", "The Rust package must be named build_broker"
    binary_targets = [t for t in packages[0]["targets"] if t["name"] == "build_broker" and "bin" in t["kind"]]
    assert binary_targets, "A Rust binary target named build_broker is required"
    assert all(t["src_path"].endswith(".rs") for t in binary_targets), "The binary target must be Rust source"

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", manifest, "--bin", "build_broker"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust project did not build:\n{build.stderr}"
    binary = os.path.join(PROJECT, "target", "debug", "build_broker")
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compiled build_broker binary is missing"

    # Replace the writable image logger with a verifier-owned in-memory WebSocket observer.
    kill_port(8080)
    kill_port(9000)

    received = queue.Queue()
    ready = threading.Event()
    stop_ws = threading.Event()
    ws_errors = queue.Queue()

    def ws_thread():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        async def handler(websocket, *args):
            if args:
                path = args[0]
            else:
                request = getattr(websocket, "request", None)
                path = getattr(request, "path", None) or getattr(websocket, "path", None)
            async for message in websocket:
                received.put((path, message))

        async def run_server():
            import websockets
            server = await websockets.serve(handler, "127.0.0.1", 9000)
            ready.set()
            try:
                while not stop_ws.is_set():
                    await asyncio.sleep(0.03)
            finally:
                server.close()
                await server.wait_closed()

        try:
            loop.run_until_complete(run_server())
        except BaseException as error:
            ws_errors.put(error)
            ready.set()
        finally:
            loop.close()

    thread = threading.Thread(target=ws_thread, daemon=True)
    thread.start()
    assert ready.wait(5), "WebSocket observer did not start"
    assert ws_errors.empty(), f"WebSocket observer failed: {ws_errors.get()}"

    broker = None
    log_handle = None
    try:
        log_handle = open("/home/user/broker.log", "wb")
        broker = subprocess.Popen(
            [binary],
            cwd=PROJECT,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
        )

        deadline = time.time() + 10
        while time.time() < deadline:
            assert broker.poll() is None, "Compiled Rust broker exited before accepting requests"
            try:
                if post("java", "CMD javac\nRUN", timeout=0.5) == 400:
                    break
            except (OSError, urllib.error.URLError):
                pass
            time.sleep(0.1)
        else:
            raise AssertionError("Compiled Rust broker did not listen on 127.0.0.1:8080")

        assert broker.pid in listener_pids(8080), "The compiled Rust process is not the HTTP listener on port 8080"

        token = secrets.token_hex(16)
        no_run_cmd = f"never-dispatch-{token}"
        assert post("rust", f"ENV QUIET=yes\nCMD {no_run_cmd}\n\n") == 200
        time.sleep(0.3)
        assert all(no_run_cmd not in str(item) for item in list(received.queue)), "A script without RUN was dispatched"

        # Avoid ambiguity over whether a successful no-RUN request consumes its target's rate window.
        time.sleep(0.9)

        cpp_cmd = f"clang++ source_{token}.cpp"
        cpp_rejected = f"rejected-cpp-{token}"
        cpp_script = f"ENV OPT=-O3\nCMD {cpp_cmd}\nENV TOKEN={token}=tail\nRUN\nCMD ignored-{token}\nENV AFTER=bad"
        assert post("cpp", cpp_script) == 200
        assert post("cpp", f"CMD {cpp_rejected}\nRUN") == 429

        rust_cmd = f"cargo build --package pkg_{token}"
        rust_rejected = f"rejected-rust-{token}"
        rust_script = f"CMD {rust_cmd}\nENV MODE=release\nENV ID={token}\nRUN\nCMD ignored-rust-{token}"
        assert post("rust", rust_script) == 200, "Rate limiting was not independent per target"
        assert post("rust", f"CMD {rust_rejected}\nRUN") == 429

        time.sleep(1.15)
        cpp_cmd2 = f"g++ later_{token}.cc"
        rust_cmd2 = f"rustc later_{token}.rs"
        assert post("cpp", f"CMD {cpp_cmd2}\nRUN") == 200
        assert post("rust", f"ENV PASS=two\nCMD {rust_cmd2}\nRUN") == 200

        deadline = time.time() + 5
        captured = []
        while time.time() < deadline and len(captured) < 4:
            try:
                captured.append(received.get(timeout=0.15))
            except queue.Empty:
                pass

        assert broker.poll() is None, "Compiled Rust broker exited during testing"
        assert len(captured) == 4, f"Expected four WebSocket messages, received {len(captured)}"
        assert all(path == "/dispatch" for path, _ in captured), "Broker connected to the wrong WebSocket path"
        assert all(isinstance(message, str) for _, message in captured), "Jobs must be WebSocket text messages"

        jobs = []
        for _, message in captured:
            try:
                jobs.append(json.loads(message))
            except json.JSONDecodeError as error:
                raise AssertionError(f"WebSocket message was not valid JSON: {message!r}") from error

        expected = {
            cpp_cmd: {"target": "cpp", "cmd": cpp_cmd, "env": {"OPT": "-O3", "TOKEN": token + "=tail"}},
            rust_cmd: {"target": "rust", "cmd": rust_cmd, "env": {"MODE": "release", "ID": token}},
            cpp_cmd2: {"target": "cpp", "cmd": cpp_cmd2, "env": {}},
            rust_cmd2: {"target": "rust", "cmd": rust_cmd2, "env": {"PASS": "two"}},
        }
        by_command = {job.get("cmd"): job for job in jobs if isinstance(job, dict)}
        for command, wanted in expected.items():
            assert by_command.get(command) == wanted, f"Incorrect dispatched job for {command!r}: {by_command.get(command)!r}"
        assert cpp_rejected not in by_command and rust_rejected not in by_command, "A rate-limited job was dispatched"
        assert no_run_cmd not in by_command, "A no-RUN job was dispatched"
    finally:
        if broker is not None and broker.poll() is None:
            broker.terminate()
            try:
                broker.wait(timeout=3)
            except subprocess.TimeoutExpired:
                broker.kill()
                broker.wait(timeout=3)
        if log_handle is not None:
            log_handle.close()
        stop_ws.set()
        thread.join(timeout=3)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_build_broker.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
