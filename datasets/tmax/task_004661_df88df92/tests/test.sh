#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pwd
import signal
import socket
import subprocess
import time
import urllib.request

import pytest

USER = pwd.getpwnam("user")
PORTS = (9001, 9002, 9003, 8080)


def as_user():
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def spawn(cmd, **kwargs):
    return subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        preexec_fn=as_user,
        **kwargs,
    )


def listening_inodes(ports):
    wanted = set(ports)
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port in wanted:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def pid_listening_ports(pid):
    inode_to_port = {}
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        inode_to_port[fields[9]] = int(fields[1].rsplit(":", 1)[1], 16)
        except FileNotFoundError:
            pass

    ports = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:["):
                inode = target[8:-1]
                if inode in inode_to_port:
                    ports.add(inode_to_port[inode])
    except (FileNotFoundError, PermissionError):
        pass
    return ports


def kill_listeners(ports):
    inodes = listening_inodes(ports)
    if not inodes:
        return
    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            for fd in os.listdir(f"/proc/{entry}/fd"):
                try:
                    target = os.readlink(f"/proc/{entry}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.6)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def clear_pid_files():
    run_dir = "/home/user/services/run"
    if os.path.isdir(run_dir):
        for name in os.listdir(run_dir):
            path = os.path.join(run_dir, name)
            if os.path.isfile(path) or os.path.islink(path):
                try:
                    os.unlink(path)
                except OSError:
                    pass


def wait_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"port {port} did not begin listening")


def get(url, timeout=2):
    req = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200
        return response.read().decode("ascii").strip()


def launch_backends():
    clear_pid_files()
    proc = spawn(["python3", "/home/user/start_backends.py"], cwd="/home/user")
    time.sleep(1.5)
    if proc.poll() not in (None, 0):
        pytest.fail(f"start_backends.py exited with status {proc.returncode}")
    for port in (9001, 9002, 9003):
        wait_port(port)
    return proc


def launch_proxy():
    proc = spawn(["python3", "/home/user/proxy.py"], cwd="/home/user")
    time.sleep(0.8)
    if proc.poll() is not None:
        pytest.fail(f"proxy.py exited with status {proc.returncode}")
    wait_port(8080)
    return proc


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def read_pid_files():
    values = []
    run_dir = "/home/user/services/run"
    for name in os.listdir(run_dir):
        path = os.path.join(run_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path) as f:
                value = int(f.read().strip())
            os.kill(value, 0)
            values.append(value)
        except (ValueError, OSError):
            continue
    return values


def test_directories_and_symlink():
    assert os.path.isdir("/home/user/services/logs"), "/home/user/services/logs directory is missing"
    assert os.path.isdir("/home/user/services/run"), "/home/user/services/run directory is missing"

    symlink_path = "/home/user/logs"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"

    target = os.readlink(symlink_path)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
    assert target == "/home/user/services/logs", f"Symlink {symlink_path} does not point to /home/user/services/logs"


def test_scripts_exist():
    assert os.path.isfile("/home/user/start_backends.py"), "/home/user/start_backends.py is missing"
    assert os.path.isfile("/home/user/proxy.py"), "/home/user/proxy.py is missing"


def test_perturbation_removed():
    client_py_path = "/app/vendored/netprobe-1.0.0/netprobe/client.py"
    assert os.path.isfile(client_py_path), f"client.py missing: {client_py_path}"

    with open(client_py_path, "r") as f:
        content = f.read()

    for line in content.splitlines():
        if "time.sleep(0.1)" in line:
            assert line.lstrip().startswith("#"), "The blocking 'time.sleep(0.1)' is still present and not commented out in client.py"


def test_live_backends_proxy_and_netprobe():
    counter_source = r'''
import asyncio, os, signal
port = int(os.environ["TEST_PORT"])
marker = os.environ["TEST_MARKER"].encode()
out = os.environ["TEST_COUNT_FILE"]
count = 0
stop = asyncio.Event()
async def handle(reader, writer):
    global count
    try:
        await reader.readuntil(b"\\r\\n\\r\\n")
        count += 1
        body = marker
        writer.write(b"HTTP/1.1 200 OK\\r\\nContent-Length: " + str(len(body)).encode() + b"\\r\\nConnection: close\\r\\n\\r\\n" + body)
        await writer.drain()
    except Exception:
        pass
    writer.close()
    try: await writer.wait_closed()
    except Exception: pass
async def main():
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    server = await asyncio.start_server(handle, "127.0.0.1", port, backlog=512)
    await stop.wait()
    server.close()
    await server.wait_closed()
try:
    asyncio.run(main())
finally:
    with open(out, "w") as f: f.write(str(count))
'''
    counter_path = "/tmp/verifier_counter_backend.py"
    with open(counter_path, "w") as f:
        f.write(counter_source)
    os.chmod(counter_path, 0o644)

    backend_launcher = proxy_proc = None
    counters = []
    try:
        kill_listeners(PORTS)
        backend_launcher = launch_backends()

        # Confirm the PID files identify three live backend listeners, not arbitrary values.
        pids = read_pid_files()
        assert len(set(pids)) >= 3, "three valid backend PID files were not created"
        covered = set()
        for pid in set(pids):
            covered.update(pid_listening_ports(pid))
        assert {9001, 9002, 9003}.issubset(covered), "PID files do not identify listeners on all backend ports"

        for port in (9001, 9002, 9003):
            get(f"http://127.0.0.1:{port}/")

        proxy_proc = launch_proxy()
        get("http://127.0.0.1:8080/")

        # Replace the indistinguishable simple backends with verifier-controlled
        # marker/counting servers so round-robin and real request volume can be observed.
        stop_process(proxy_proc)
        stop_process(backend_launcher)
        kill_listeners(PORTS)
        counters = []
        for index, port in enumerate((9001, 9002, 9003), 1):
            count_file = f"/tmp/netprobe_count_{port}"
            try:
                os.unlink(count_file)
            except FileNotFoundError:
                pass
            env = os.environ.copy()
            env.update(TEST_PORT=str(port), TEST_MARKER=str(index), TEST_COUNT_FILE=count_file)
            counters.append((spawn(["python3", counter_path], env=env), count_file))
        for port in (9001, 9002, 9003):
            wait_port(port)

        proxy_proc = launch_proxy()
        sequence = [get("http://127.0.0.1:8080/rr") for _ in range(6)]
        assert sequence in (["1", "2", "3", "1", "2", "3"], ["2", "3", "1", "2", "3", "1"], ["3", "1", "2", "3", "1", "2"]), f"proxy is not round-robin: {sequence}"

        # Restart counters to exclude the functional probes from the measured run.
        stop_process(proxy_proc)
        for proc, _ in counters:
            stop_process(proc)
        kill_listeners(PORTS)
        counters = []
        for index, port in enumerate((9001, 9002, 9003), 1):
            count_file = f"/tmp/netprobe_count_{port}"
            try:
                os.unlink(count_file)
            except FileNotFoundError:
                pass
            env = os.environ.copy()
            env.update(TEST_PORT=str(port), TEST_MARKER=str(index), TEST_COUNT_FILE=count_file)
            counters.append((spawn(["python3", counter_path], env=env), count_file))
        for port in (9001, 9002, 9003):
            wait_port(port)
        proxy_proc = launch_proxy()

        results_path = "/home/user/probe_results.json"
        try:
            os.unlink(results_path)
        except FileNotFoundError:
            pass
        started = time.monotonic()
        completed = subprocess.run(
            ["python3", "-m", "netprobe", "--url", "http://127.0.0.1:8080", "--duration", "5", "--output", results_path],
            cwd="/home/user",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
            preexec_fn=as_user,
        )
        elapsed = time.monotonic() - started
        assert completed.returncode == 0, f"netprobe failed: {completed.stdout}"
        assert 4.5 <= elapsed <= 12, f"netprobe did not perform a five-second load test (elapsed {elapsed:.2f}s)"

        stop_process(proxy_proc)
        proxy_proc = None
        for proc, _ in counters:
            stop_process(proc)
        counts = []
        for _, path in counters:
            with open(path) as f:
                counts.append(int(f.read().strip()))
        total = sum(counts)
        measured_rps = total / elapsed
        assert measured_rps >= 200.0, f"observed throughput below 200 RPS: {measured_rps:.2f} ({total} requests)"
        assert min(counts) >= total * 0.25, f"load was not distributed across all backends: {counts}"

        with open(results_path) as f:
            reported = float(json.load(f).get("requests_per_second", 0))
        assert math.isfinite(reported), "netprobe reported a non-finite RPS"
        assert reported >= 200.0, f"RPS metric threshold not met. Expected >= 200.0, got {reported}"
        assert reported <= measured_rps * 1.20 + 5, f"netprobe over-reported throughput: reported {reported:.2f}, observed {measured_rps:.2f}"
    finally:
        stop_process(proxy_proc)
        for proc, _ in counters:
            stop_process(proc)
        stop_process(backend_launcher)
        kill_listeners(PORTS)
        # Leave the submitted backends and proxy running as required by the task.
        try:
            backend_launcher = launch_backends()
            launch_proxy()
        except Exception:
            pass


def test_metric_threshold():
    results_path = "/home/user/probe_results.json"
    assert os.path.isfile(results_path), f"Results file missing: {results_path}. The load test was not run or didn't save output."

    try:
        with open(results_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Results file {results_path} is not valid JSON.")

    rps = float(data.get("requests_per_second", 0))
    assert rps >= 200.0, f"RPS metric threshold not met. Expected >= 200.0, got {rps}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
