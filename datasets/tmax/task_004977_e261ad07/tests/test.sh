#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import json
import math
import os
import random
import signal
import struct
import subprocess
import tempfile
import time
import wave

import numpy as np
import requests

LIB_PATH = "/home/user/libcode.so"
DATA_A = "/app/data_A.b64"
DATA_B = "/app/data_B.b64"
BASE_URL = "http://127.0.0.1:8888"


def decode_signal(path):
    with wave.open(path, "rb") as wav:
        assert wav.getnchannels() == 1
        rate = wav.getframerate()
        width = wav.getsampwidth()
        raw = wav.readframes(wav.getnframes())
    assert width == 2
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float64)

    window = max(256, int(rate * 0.02))
    energies = []
    for start in range(0, len(samples), window):
        chunk = samples[start:start + window]
        energies.append(float(np.sqrt(np.mean(chunk * chunk))) if len(chunk) else 0.0)
    threshold = max(100.0, max(energies) * 0.15)

    regions = []
    start_window = None
    for index, energy in enumerate(energies + [0.0]):
        if energy > threshold and start_window is None:
            start_window = index
        elif energy <= threshold and start_window is not None:
            if index - start_window >= 2:
                regions.append((start_window * window, min(index * window, len(samples))))
            start_window = None

    rows = [697, 770, 852, 941]
    cols = [1209, 1336, 1477]
    keypad = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"],
    ]

    def strength(chunk, frequency):
        t = np.arange(len(chunk), dtype=np.float64) / rate
        return abs(np.dot(chunk, np.exp(-2j * math.pi * frequency * t)))

    decoded = []
    for begin, end in regions:
        chunk = samples[begin:end]
        row = max(range(len(rows)), key=lambda i: strength(chunk, rows[i]))
        col = max(range(len(cols)), key=lambda i: strength(chunk, cols[i]))
        decoded.append(keypad[row][col])
    text = "".join(decoded)
    assert text and text.isdigit(), f"Signal did not decode to decimal digits: {text!r}"
    return int(text)


def decoded_data():
    lines = []
    for path in (DATA_A, DATA_B):
        with open(path, "rb") as f:
            lines.extend(base64.b64decode(f.read(), validate=False).decode("utf-8").splitlines())
    return sorted(set(lines))


def get_json(path):
    response = requests.get(BASE_URL + path, timeout=5)
    assert response.status_code == 200, (
        f"Expected HTTP 200 from {path}, got {response.status_code}: {response.text}"
    )
    try:
        return response.json()
    except ValueError as exc:
        raise AssertionError(f"Response from {path} is not valid JSON: {response.text}") from exc


def listener_pid():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 8888 and state == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass
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
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    return int(name)
        except (FileNotFoundError, PermissionError):
            continue
    return None


def capture_server():
    pid = listener_pid()
    assert pid is not None, "No process is listening on port 8888"
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode() for part in f.read().split(b"\0") if part]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/environ", "rb") as f:
        env = {}
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    assert argv, "Could not determine the server command"
    return argv, cwd, env


def stop_server():
    deadline = time.time() + 5
    while time.time() < deadline:
        pid = listener_pid()
        if pid is None:
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        for _ in range(20):
            if listener_pid() is None:
                return
            time.sleep(0.05)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        time.sleep(0.1)
    assert listener_pid() is None, "Could not stop the existing web service"


def start_server(server):
    argv, cwd, env = server
    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(BASE_URL + "/api/code", timeout=0.5)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Restarted service did not listen on port 8888: {last_error}")


def atomic_write(path, contents, mode):
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(dir=directory)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(contents)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def install_probe_library(value):
    source = f".text\n.globl get_code\n.type get_code,@function\nget_code:\n movl ${value}, %eax\n ret\n.size get_code, .-get_code\n"
    with tempfile.TemporaryDirectory() as directory:
        asm = os.path.join(directory, "probe.S")
        output = os.path.join(directory, "libcode.so")
        with open(asm, "w") as f:
            f.write(source)
        subprocess.run(
            ["gcc", "-shared", "-nostdlib", "-Wl,--build-id=none", "-o", output, asm],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with open(output, "rb") as f:
            atomic_write(LIB_PATH, f.read(), 0o755)


def test_complete_polyglot_service():
    # Preserve the original existence assertions.
    assert os.path.exists(LIB_PATH), f"Missing required shared library: {LIB_PATH}"
    assert os.path.isfile(LIB_PATH), f"Expected {LIB_PATH} to be a file."

    elf = subprocess.run(
        ["readelf", "-h", LIB_PATH], text=True, capture_output=True, check=True
    ).stdout
    assert "ELF64" in elf and "X86-64" in elf and "DYN (Shared object file)" in elf

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", "--format=posix", LIB_PATH],
        text=True,
        capture_output=True,
        check=True,
    ).stdout.splitlines()
    exported = [line.split()[0] for line in symbols if line.split()]
    assert exported == ["get_code"], f"Expected only exported get_code, found {exported}"

    expected_code = decode_signal("/app/signal.wav")
    library = ctypes.CDLL(LIB_PATH)
    assert hasattr(library, "get_code"), "Shared library does not export get_code"
    library.get_code.argtypes = []
    library.get_code.restype = ctypes.c_int
    assert library.get_code() == expected_code, "get_code() does not return the decoded signal"

    # Preserve the original endpoint assertions, including their fixed expected values.
    code_json = get_json("/api/code")
    assert "code" in code_json, f"JSON response missing 'code' key: {code_json}"
    assert code_json["code"] == 8675309, f"Expected code to be 8675309, got {code_json['code']}"
    assert code_json["code"] == expected_code

    data_json = get_json("/api/data")
    assert "data" in data_json, f"JSON response missing 'data' key: {data_json}"
    fixed_data = ["apple", "banana", "cherry", "date", "elderberry"]
    assert data_json["data"] == fixed_data, f"Expected data list {fixed_data}, got {data_json['data']}"
    assert data_json["data"] == decoded_data()

    server = capture_server()
    backups = {}
    for path in (LIB_PATH, DATA_A, DATA_B):
        with open(path, "rb") as f:
            backups[path] = (f.read(), os.stat(path).st_mode & 0o777)

    probe_code = random.SystemRandom().randint(12000000, 1900000000)
    token = os.urandom(8).hex()
    probe_a = [f"zeta-{token}", f"alpha-{token}", f"shared-{token}"]
    probe_b = [f"middle-{token}", f"shared-{token}", f"beta-{token}"]
    expected_probe_data = sorted(set(probe_a + probe_b))

    try:
        stop_server()
        install_probe_library(probe_code)
        atomic_write(DATA_A, base64.b64encode(("\n".join(probe_a) + "\n").encode()) + b"\n", 0o666)
        atomic_write(DATA_B, base64.b64encode(("\n".join(probe_b) + "\n").encode()) + b"\n", 0o666)
        start_server(server)

        dynamic_code = get_json("/api/code")
        assert dynamic_code.get("code") == probe_code, (
            "The code endpoint did not obtain its value from libcode.so at service startup"
        )
        dynamic_data = get_json("/api/data")
        assert dynamic_data.get("data") == expected_probe_data, (
            "The data endpoint did not decode, merge, sort, and deduplicate the input files"
        )
    finally:
        stop_server()
        for path, (contents, mode) in backups.items():
            atomic_write(path, contents, mode)
        start_server(server)

    # Ensure the restored service remains available with the original required outputs.
    assert get_json("/api/code").get("code") == expected_code
    assert get_json("/api/data").get("data") == fixed_data
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
