#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import signal
import socket
import subprocess
import threading
import time


def test_result_file_exists_and_correct():
    result_file = "/home/user/result.txt"
    assert os.path.exists(result_file), f"Result file {result_file} is missing."
    assert os.path.isfile(result_file), f"{result_file} is not a file."

    with open(result_file, "r") as f:
        content = f.read()

    assert "PONG_SUCCESS_8472" in content, "The result.txt file does not contain the expected response 'PONG_SUCCESS_8472'."
    assert content == "PONG_SUCCESS_8472\n", f"result.txt must contain the exact backend response, got {content!r}"


def test_bridge_script_exists():
    bridge_script = "/home/user/bridge.py"
    assert os.path.exists(bridge_script), f"Bridge script {bridge_script} is missing."
    assert os.path.isfile(bridge_script), f"{bridge_script} is not a file."


def test_bridge_is_running_and_functional():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("127.0.0.1", 8888))
        s.sendall(b"PING")
        data = s.recv(1024)
        s.close()
    except ConnectionRefusedError:
        raise AssertionError("Connection refused to 127.0.0.1:8888. Is the bridge running?")
    except socket.timeout:
        raise AssertionError("Connection to 127.0.0.1:8888 timed out.")
    except Exception as e:
        raise AssertionError(f"Failed to connect and communicate with the bridge: {e}")

    assert b"PONG_SUCCESS_8472" in data, f"Expected 'PONG_SUCCESS_8472' from bridge, got {data}"


def _pids_holding_inodes(inodes):
    found = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in wanted:
                        found.add(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return found


def _stop_socket_owners(inodes):
    pids = _pids_holding_inodes(inodes) - {os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def _tcp_listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except OSError:
            pass
    return result


def _unix_socket_inodes(path):
    result = set()
    with open("/proc/net/unix") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                result.add(fields[6])
    return result


def _latest_socket_path():
    paths = []
    with open("/home/user/service.log") as f:
        for line in f:
            marker = "Backend listening on unix socket:"
            if marker in line:
                paths.append(line.split(marker, 1)[1].strip())
    assert paths, "No backend Unix socket entry was found in service.log"
    return paths[-1]


def test_executed_bridge_really_forwards_binary_data_to_logged_unix_socket():
    socket_path = _latest_socket_path()

    # Stop the submitted background bridge and the fixed mock backend, then place
    # a verifier-controlled backend at the same latest logged socket path.
    _stop_socket_owners(_tcp_listener_inodes(8888))
    _stop_socket_owners(_unix_socket_inodes(socket_path))
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass

    unix_server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    unix_server.bind(socket_path)
    unix_server.listen(5)
    unix_server.settimeout(0.2)

    payload = b"VERIFY_BINARY\x00" + secrets.token_bytes(193)
    expected = b"DYNAMIC_RESPONSE\x00" + hashlib.sha256(payload).digest()
    stop = threading.Event()
    backend_errors = []

    def backend():
        while not stop.is_set():
            try:
                conn, _ = unix_server.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                conn.settimeout(2.0)
                data = conn.recv(65536)
                conn.sendall(b"DYNAMIC_RESPONSE\x00" + hashlib.sha256(data).digest())
            except Exception as exc:
                backend_errors.append(exc)
            finally:
                conn.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    bridge = subprocess.Popen(
        ["python3", "/home/user/bridge.py"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        deadline = time.time() + 5.0
        client = None
        while time.time() < deadline:
            if bridge.poll() is not None:
                raise AssertionError(f"Executing bridge.py exited early with status {bridge.returncode}")
            candidate = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            candidate.settimeout(2.0)
            try:
                candidate.connect(("127.0.0.1", 8888))
                client = candidate
                break
            except ConnectionRefusedError:
                candidate.close()
                time.sleep(0.05)

        assert client is not None, "Executed bridge.py did not listen on 127.0.0.1:8888"
        with client:
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        actual = b"".join(chunks)

        assert not backend_errors, f"Verifier backend failed: {backend_errors!r}"
        assert actual == expected, (
            "bridge.py did not transparently forward the verifier-generated binary "
            f"request and response; got {actual!r}"
        )
    finally:
        stop.set()
        unix_server.close()
        bridge.terminate()
        try:
            bridge.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            bridge.kill()
            bridge.wait()
        thread.join(timeout=1.0)
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
