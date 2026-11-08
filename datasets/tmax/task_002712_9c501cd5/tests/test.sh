#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import socket
import pytest

HOST = '127.0.0.1'
PORT = 8888

def send_command(cmd: bytes) -> bytes:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3.0)
            s.connect((HOST, PORT))
            s.sendall(cmd)
            data = b""
            while b'\n' not in data:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
            return data
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused. Is the C server running on {HOST}:{PORT}?")
    except socket.timeout:
        pytest.fail(f"Connection or read timed out while communicating with {HOST}:{PORT}.")
    except Exception as e:
        pytest.fail(f"Failed to communicate with server on {HOST}:{PORT}: {e}")

def test_auth_command():
    response = send_command(b"AUTH\n")
    expected = b"ECHO\n"
    assert response == expected, f"AUTH command failed. Expected {expected!r}, got {response!r}"

def test_corrupted_command():
    response = send_command(b"CORRUPTED\n")
    expected = b"archive_02.zip,archive_05.tar.gz\n"
    assert response == expected, f"CORRUPTED command failed. Expected {expected!r}, got {response!r}"

def test_total_bytes_command():
    response = send_command(b"TOTAL_BYTES\n")
    expected = b"8675309\n"
    assert response == expected, f"TOTAL_BYTES command failed. Expected {expected!r}, got {response!r}"
TEST_EOF

cat << 'CHECK_EOF' > /tmp/check_c_server.py
import csv
import os
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import wave
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8888


def derive_auth():
    words = [
        "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
        "hotel", "india", "juliett", "kilo", "lima", "mike", "november",
        "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform",
        "victor", "whiskey", "x-ray", "yankee", "zulu"
    ]
    with wave.open("/app/voicemail.wav", "rb") as w:
        target_params = w.getparams()[:4]
        target_frames = w.readframes(w.getnframes())

    matches = []
    with tempfile.TemporaryDirectory() as td:
        for word in words:
            out = os.path.join(td, word + ".wav")
            sentence = (
                "The system is failing. The emergency authorization code is "
                + word + ". I repeat, " + word + "."
            )
            subprocess.run(
                ["espeak", "-w", out, sentence],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            with wave.open(out, "rb") as w:
                params = w.getparams()[:4]
                frames = w.readframes(w.getnframes())
            if params == target_params and frames == target_frames:
                matches.append(word)
    if len(matches) != 1:
        raise AssertionError(f"Could not uniquely derive authorization word from voicemail: {matches}")
    return matches[0].upper()


def parse_manifest(raw):
    text = raw.decode("utf-16le")
    root = ET.fromstring(text)
    value = root.findtext(".//bytes")
    if value is None:
        raise ValueError("manifest has no bytes element")
    return int(value.strip())


def derive_archive_results():
    with open("/app/inventory.csv", newline="") as f:
        names = [row["filename"] for row in csv.DictReader(f)]

    corrupted = []
    total = 0
    for name in names:
        path = os.path.join("/app/storage", name)
        try:
            if name.endswith(".zip"):
                with zipfile.ZipFile(path) as archive:
                    if archive.testzip() is not None:
                        raise ValueError("ZIP CRC failure")
                    manifest = archive.read("manifest.xml")
            elif name.endswith(".tar.gz"):
                with tarfile.open(path, "r:gz") as archive:
                    manifest = None
                    for member in archive.getmembers():
                        if member.isfile():
                            handle = archive.extractfile(member)
                            data = handle.read() if handle is not None else b""
                            if Path(member.name).name == "manifest.xml":
                                manifest = data
                    if manifest is None:
                        raise ValueError("manifest.xml missing")
            else:
                raise ValueError("unsupported archive type")
            total += parse_manifest(manifest)
        except Exception:
            corrupted.append(name)
    return ",".join(sorted(corrupted)), total


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == PORT:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_listener():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2.0
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def request(command):
    with socket.create_connection((HOST, PORT), timeout=1.0) as s:
        s.settimeout(1.0)
        s.sendall(command)
        data = b""
        while b"\n" not in data:
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
        return data


def wait_for_server(proc):
    deadline = time.time() + 2.5
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.15):
                return True
        except OSError:
            if proc.poll() is not None and not listener_pids():
                return False
            time.sleep(0.05)
    return False


def compile_candidates():
    sources = []
    for root in (Path("/app"), Path("/home/user"), Path("/tmp")):
        if root.exists():
            sources.extend(p for p in root.rglob("*.c") if p.is_file())
    sources = sorted(set(sources))
    if not sources:
        raise AssertionError("No C source file was found")

    build_dir = Path(tempfile.mkdtemp(prefix="verified-c-server-"))
    command_sets = [(src,) for src in sources]
    for directory in sorted(set(src.parent for src in sources)):
        group = tuple(src for src in sources if src.parent == directory)
        if len(group) > 1:
            command_sets.append(group)

    binaries = []
    for index, group in enumerate(command_sets):
        output = build_dir / f"server-{index}"
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-pthread", *map(str, group), "-lm", "-o", str(output)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
        if result.returncode == 0:
            with open(output, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    binaries.append(output)
    if not binaries:
        raise AssertionError("The submitted C source could not be compiled into an ELF executable")
    return binaries


auth = derive_auth()
corrupted, total = derive_archive_results()
expected = {
    b"AUTH\n": (auth + "\n").encode(),
    b"CORRUPTED\n": (corrupted + "\n").encode(),
    b"TOTAL_BYTES\n": (str(total) + "\n").encode(),
}

# Preserve the task's known assertions while also deriving them from the actual inputs.
assert expected[b"AUTH\n"] == b"ECHO\n"
assert expected[b"CORRUPTED\n"] == b"archive_02.zip,archive_05.tar.gz\n"
assert expected[b"TOTAL_BYTES\n"] == b"8675309\n"

binaries = compile_candidates()
stop_listener()
errors = []
for binary in binaries:
    stop_listener()
    proc = subprocess.Popen(
        [str(binary)],
        cwd=str(binary.parent),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        if not wait_for_server(proc):
            errors.append(f"{binary}: did not listen on port 8888")
            continue
        for _ in range(2):
            for command in (b"TOTAL_BYTES\n", b"AUTH\n", b"CORRUPTED\n"):
                actual = request(command)
                if actual != expected[command]:
                    raise AssertionError(
                        f"{binary} returned {actual!r} for {command!r}; expected {expected[command]!r}"
                    )
        raise SystemExit(0)
    except (OSError, AssertionError) as exc:
        errors.append(str(exc))
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop_listener()

raise AssertionError("No submitted C server passed the protocol tests: " + "; ".join(errors))
CHECK_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/check_c_server.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
