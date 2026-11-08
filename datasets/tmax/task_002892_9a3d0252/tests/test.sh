#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import signal
import socket
import struct
import subprocess
import time
import wave

import requests

PROJECT = "/home/user/project"
HTTP_PORT = 8080
GRPC_PORT = 50051
TOKEN = "Bearer polyglot-auth-token"


def wait_for_port(port, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.2)
    return False


def listener_inodes(port):
    answer = set()
    wanted = "%04X" % port
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                answer.add(fields[9])
    return answer


def pids_for_inodes(inodes):
    found = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(pid)
        except OSError:
            pass
    return found


def stop_old_listeners():
    pids = pids_for_inodes(listener_inodes(HTTP_PORT) | listener_inodes(GRPC_PORT))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    end = time.time() + 4
    while time.time() < end and (listener_inodes(HTTP_PORT) or listener_inodes(GRPC_PORT)):
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def all_sources(ext):
    return glob.glob(os.path.join(PROJECT, "**", "*" + ext), recursive=True)


def test_build_and_required_artifacts():
    build = os.path.join(PROJECT, "build.sh")
    assert os.path.isfile(build), "Missing /home/user/project/build.sh"
    script = open(build, errors="ignore").read()
    assert re.search(r"go\s+build", script), "build.sh does not build the Go library"
    assert "buildmode=c-shared" in script, "Go library is not built with -buildmode=c-shared"
    assert re.search(r"cargo\s+(build|run)", script), "build.sh does not build the Rust application"

    go_files = all_sources(".go")
    rust_files = all_sources(".rs")
    proto_files = all_sources(".proto")
    assert go_files, "No Go source files found"
    assert rust_files, "No Rust source files found"
    assert proto_files, "No protobuf definition found"

    go_src = "\n".join(open(p, errors="ignore").read() for p in go_files)
    rust_src = "\n".join(open(p, errors="ignore").read() for p in rust_files)
    proto_src = "\n".join(open(p, errors="ignore").read() for p in proto_files)
    assert re.search(r"//export\s+EvaluateAudio", go_src), "Go does not export EvaluateAudio"
    assert re.search(r"func\s+EvaluateAudio\s*\(", go_src), "EvaluateAudio implementation missing"
    assert re.search(r"\bgo\s+(?:func\b|[A-Za-z_]\w*\s*\()", go_src), "No goroutine-based audio processing found"
    assert ("sync." in go_src or re.search(r"\bchan\b", go_src)), "No Go synchronization/channel use found"
    assert "EvaluateAudio" in rust_src and re.search(r"extern\s+\"C\"", rust_src), "Rust FFI declaration for EvaluateAudio missing"
    assert re.search(r"service\s+MathSolver\b", proto_src), "MathSolver protobuf service missing"
    assert re.search(r"rpc\s+SolveAudio\s*\(", proto_src), "SolveAudio RPC missing"

    stop_old_listeners()
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + ":" + env.get("LD_LIBRARY_PATH", "")
    try:
        result = subprocess.run(["bash", build], cwd=PROJECT, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=240)
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("build.sh did not finish and leave the server in the background") from exc
    assert result.returncode == 0, "build.sh failed:\n" + result.stdout[-5000:]

    assert wait_for_port(HTTP_PORT), "HTTP server is not listening on port 8080"
    assert wait_for_port(GRPC_PORT), "gRPC server is not listening on port 50051"

    libraries = glob.glob(os.path.join(PROJECT, "**", "libaudio.so"), recursive=True)
    assert libraries, "libaudio.so was not produced"
    lib = libraries[0]
    assert open(lib, "rb").read(4) == b"\x7fELF", "libaudio.so is not an ELF shared library"
    nm = subprocess.run(["nm", "-D", lib], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert nm.returncode == 0 and re.search(r"\bEvaluateAudio$", nm.stdout, re.M), "libaudio.so does not export EvaluateAudio"


def test_servers_are_one_rust_binary_using_libaudio():
    http_pids = pids_for_inodes(listener_inodes(HTTP_PORT))
    grpc_pids = pids_for_inodes(listener_inodes(GRPC_PORT))
    common = http_pids & grpc_pids
    assert common, "HTTP and gRPC are not exposed by the same Rust edge process"
    valid = []
    for pid in common:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if open(exe, "rb").read(4) != b"\x7fELF":
                continue
            maps = open(f"/proc/{pid}/maps", errors="ignore").read()
            if "libaudio.so" in maps:
                valid.append(pid)
        except OSError:
            pass
    assert valid, "The edge process is not an ELF application with libaudio.so loaded"


def test_http_endpoint_authorized():
    assert wait_for_port(HTTP_PORT), "HTTP server is not listening on port 8080"
    response = requests.get("http://127.0.0.1:8080/solve/dtmf",
                            headers={"Authorization": TOKEN}, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        raise AssertionError(f"Expected JSON response, got: {response.text}")
    assert "result" in data, "Response JSON missing 'result' key"
    assert str(data["result"]) == "42", f"Expected result 42, got {data['result']}"


def test_http_endpoint_unauthorized():
    assert wait_for_port(HTTP_PORT), "HTTP server is not listening on port 8080"
    response = requests.get("http://127.0.0.1:8080/solve/dtmf", timeout=5)
    assert response.status_code == 401, f"Expected status code 401 for unauthorized request, got {response.status_code}"


def test_grpc_port_listening():
    assert wait_for_port(GRPC_PORT), "gRPC server is not listening on port 50051"


DTMF = {
    "1": (697, 1209), "2": (697, 1336), "3": (697, 1477), "A": (697, 1633),
    "4": (770, 1209), "5": (770, 1336), "6": (770, 1477), "B": (770, 1633),
    "7": (852, 1209), "8": (852, 1336), "9": (852, 1477), "C": (852, 1633),
    "0": (941, 1336), "D": (941, 1633),
}


def write_wav(path, expression, rate=8000):
    samples = []
    for char in expression:
        f1, f2 = DTMF[char]
        for i in range(int(0.20 * rate)):
            t = i / rate
            value = int(0.5 * 32767 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
            samples.append(max(-32768, min(32767, value)))
        samples.extend([0] * int(0.10 * rate))
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(struct.pack("<%dh" % len(samples), *samples))


def hpack_int(value, prefix_bits, first=0):
    limit = (1 << prefix_bits) - 1
    if value < limit:
        return bytes([first | value])
    out = bytearray([first | limit])
    value -= limit
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def hpack_string(value):
    raw = value.encode()
    return hpack_int(len(raw), 7) + raw


def literal_indexed_name(index, value):
    return hpack_int(index, 4) + hpack_string(value)


def literal_new(name, value):
    return b"\x00" + hpack_string(name) + hpack_string(value)


def frame(frame_type, flags, stream, payload=b""):
    return len(payload).to_bytes(3, "big") + bytes([frame_type, flags]) + (stream & 0x7fffffff).to_bytes(4, "big") + payload


def recv_exact(sock, count):
    data = b""
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise AssertionError("gRPC server closed the connection early")
        data += part
    return data


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def read_varint(data, offset):
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, offset
        shift += 7
    raise AssertionError("Truncated protobuf varint")


def grpc_method_path():
    for path in all_sources(".proto"):
        src = open(path, errors="ignore").read()
        if re.search(r"service\s+MathSolver\b", src) and re.search(r"rpc\s+SolveAudio\s*\(", src):
            match = re.search(r"\bpackage\s+([\w.]+)\s*;", src)
            prefix = (match.group(1) + ".") if match else ""
            return "/" + prefix + "MathSolver/SolveAudio"
    raise AssertionError("Could not determine SolveAudio gRPC method path")


def grpc_solve(filepath):
    path = grpc_method_path()
    headers = b"".join([
        b"\x83",                         # :method POST
        b"\x86",                         # :scheme http
        literal_indexed_name(4, path),     # :path
        literal_indexed_name(1, "127.0.0.1:50051"),
        literal_indexed_name(31, "application/grpc"),
        literal_new("te", "trailers"),
    ])
    raw_path = filepath.encode()
    protobuf = b"\x0a" + varint(len(raw_path)) + raw_path
    message = b"\x00" + len(protobuf).to_bytes(4, "big") + protobuf

    sock = socket.create_connection(("127.0.0.1", GRPC_PORT), timeout=5)
    sock.settimeout(8)
    try:
        sock.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + frame(4, 0, 0))
        sock.sendall(frame(1, 4, 1, headers) + frame(0, 1, 1, message))
        data = b""
        deadline = time.time() + 8
        while time.time() < deadline:
            header = recv_exact(sock, 9)
            length = int.from_bytes(header[:3], "big")
            ftype, flags = header[3], header[4]
            stream = int.from_bytes(header[5:9], "big") & 0x7fffffff
            payload = recv_exact(sock, length)
            if ftype == 4 and not (flags & 1):
                sock.sendall(frame(4, 1, 0))
            if ftype == 0 and stream == 1:
                data += payload
                if len(data) >= 5 and len(data) >= 5 + int.from_bytes(data[1:5], "big"):
                    break
        assert len(data) >= 5, "gRPC SolveAudio returned no response message"
        assert data[0] == 0, "Compressed gRPC response was not expected"
        size = int.from_bytes(data[1:5], "big")
        body = data[5:5 + size]
        assert len(body) == size, "Truncated gRPC response"
        assert body and body[0] == 0x08, "SolveResponse does not contain int32 result field 1"
        result, _ = read_varint(body, 1)
        return result
    finally:
        sock.close()


def test_grpc_decodes_generated_audio_and_honors_filepath():
    rng = random.SystemRandom()
    cases = []
    a, b = rng.randint(1, 9), rng.randint(1, 9)
    cases.append((f"{a}A{b}", a + b))
    a, b = rng.randint(5, 9), rng.randint(1, 4)
    cases.append((f"{a}B{b}", a - b))
    a, b = rng.randint(2, 9), rng.randint(2, 9)
    cases.append((f"{a}C{b}", a * b))
    a, b = random.choice([(8, 2), (9, 3), (6, 2), (4, 2)])
    cases.append((f"{a}D{b}", a // b))

    for index, (expression, expected) in enumerate(cases):
        filepath = f"/tmp/verifier_dtmf_{os.getpid()}_{index}.wav"
        write_wav(filepath, expression)
        try:
            actual = grpc_solve(filepath)
            assert actual == expected, f"gRPC decoded {expression} as {actual}, expected {expected}"
        finally:
            try:
                os.unlink(filepath)
            except OSError:
                pass
PYTEST

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
