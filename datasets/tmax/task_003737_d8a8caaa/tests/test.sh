#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_metrics_server.py
import base64
import os
import secrets
import signal
import socket
import subprocess
import time

SOURCE = "/home/user/metrics_server.c"
BINARY = "/home/user/metrics_server"
ASAN_BINARY = "/tmp/metrics_server_asan"
HOST = "127.0.0.1"
PORT = 9090


def listener_inodes():
    found = set()
    try:
        with open("/proc/net/tcp", "r", encoding="ascii") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) < 10:
                    continue
                local, state, inode = fields[1], fields[3], fields[9]
                address, port_hex = local.split(":")
                if address == "0100007F" and int(port_hex, 16) == PORT and state == "0A":
                    found.add(inode)
    except FileNotFoundError:
        pass
    return found


def listener_pids():
    inodes = listener_inodes()
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
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def assert_listener_is(expected_binary):
    pids = listener_pids()
    assert pids, "Service is not listening on 127.0.0.1:9090"
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", expected_binary):
                matching.append(pid)
        except OSError:
            pass
    assert matching, f"Port 9090 is not owned by the compiled executable {expected_binary}"
    return matching


def stop_listener():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2.0
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    if listener_inodes():
        for pid in listener_pids():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2.0
        while listener_inodes() and time.time() < deadline:
            time.sleep(0.05)
    assert not listener_inodes(), "Could not stop the existing service on port 9090"


def compile_binary(output, sanitize=False):
    command = ["gcc"]
    if sanitize:
        command += ["-fsanitize=address", "-fno-omit-frame-pointer", "-g"]
    command += [SOURCE, "-o", output]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert result.returncode == 0, f"Source did not compile:\n{result.stderr}"
    assert os.path.isfile(output), f"Compilation did not create {output}"
    assert os.access(output, os.X_OK), f"Compiled artifact {output} is not executable"
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled artifact {output} is not an ELF binary"


def launch(binary, asan=False):
    env = os.environ.copy()
    if asan:
        env["ASAN_OPTIONS"] = "abort_on_error=1:detect_leaks=0"
    process = subprocess.Popen([binary], stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               env=env, start_new_session=True)
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"{binary} exited before listening on port 9090")
        if listener_inodes():
            assert_listener_is(binary)
            return process
        time.sleep(0.05)
    raise AssertionError(f"{binary} did not listen on 127.0.0.1:9090")


def request(payload):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3.0)
            s.connect((HOST, PORT))
            s.sendall(payload)
            response = bytearray()
            while b"\n" not in response:
                chunk = s.recv(1024)
                if not chunk:
                    break
                response.extend(chunk)
            return bytes(response)
    except ConnectionRefusedError:
        raise AssertionError("Service is not listening on 127.0.0.1:9090")
    except socket.timeout:
        raise AssertionError("Service timed out while handling a payload")


def test_binary_exists():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}. Did you compile the C code?"


def test_service_handles_overflow_payload():
    payload = b"U3VwZXJMb25nQ29ycnVwdGVkUGF5bG9hZFRoYXRDcmFzaGVzVGhlU2VydmVy\n"
    response = request(payload)
    assert response.decode("utf-8") == "ERR: OVERFLOW\n", f"Expected 'ERR: OVERFLOW\\n', but got {response!r}"


def test_service_handles_valid_payload():
    payload = b"U2hvcnRQYXlsb2Fk\n"
    response = request(payload)
    assert response.decode("utf-8") == "OK\n", f"Expected 'OK\\n', but got {response!r}"


def make_fuzz_cases():
    lengths = [0, 1, 2, 15, 16, 17, 18, 31, 32, 63, 64, 127, 128, 199, 200]
    lengths += [secrets.randbelow(201) for _ in range(32)]
    cases = []
    for length in lengths:
        raw = secrets.token_bytes(length)
        wire = base64.b64encode(raw) + b"\n"
        decoded = base64.b64decode(wire.strip(), validate=True)
        expected = b"OK\n" if len(decoded) <= 16 else b"ERR: OVERFLOW\n"
        cases.append((wire, expected, len(decoded)))
    return cases


def test_boundaries_and_random_fuzz(cases, expected_binary):
    for wire, expected, decoded_length in cases:
        response = request(wire)
        assert response == expected, (
            f"Decoded length {decoded_length}: expected {expected!r}, got {response!r}"
        )
        assert_listener_is(expected_binary)


def run_suite(cases, expected_binary):
    test_service_handles_overflow_payload()
    assert_listener_is(expected_binary)
    test_service_handles_valid_payload()
    assert_listener_is(expected_binary)
    test_boundaries_and_random_fuzz(cases, expected_binary)


def main():
    test_binary_exists()
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable"

    # Ensure the service initially left by the agent is the demanded artifact.
    assert_listener_is(BINARY)
    cases = make_fuzz_cases()

    # Rebuild the submitted C source with AddressSanitizer and exercise it so
    # boundary behavior cannot hide an actual stack/heap buffer overflow.
    stop_listener()
    compile_binary(ASAN_BINARY, sanitize=True)
    launch(ASAN_BINARY, asan=True)
    run_suite(cases, ASAN_BINARY)

    # Rebuild with the exact requested command shape, execute that artifact,
    # repeat the behavioral checks, and leave it running for the harness.
    stop_listener()
    compile_binary(BINARY, sanitize=False)
    launch(BINARY, asan=False)
    run_suite(cases, BINARY)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_metrics_server.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
