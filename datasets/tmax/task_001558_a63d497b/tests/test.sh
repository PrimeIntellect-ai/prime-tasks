#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import signal
import socket
import stat
import struct
import subprocess
import time
import zlib

import pytest

HOST = "127.0.0.1"
PORT = 8888
SERVER = "/home/user/config_server"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_existing_server():
    pids = listener_pids(PORT)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def build_runtime_fixture():
    global EXPECTED_FILES, EXPECTED_HISTORY, FRAME_NUMBERS

    token = secrets.token_hex(8)
    dynamic_dir = f"runtime_{token}"
    dynamic_json = json.dumps(
        {"token": token, "value": secrets.randbits(48)},
        separators=(",", ":"),
    ).encode() + b"\n"
    dynamic_text = b"runtime-" + secrets.token_bytes(24) + b"\x00\n"

    root = "/app/configs"
    os.makedirs(os.path.join(root, dynamic_dir), exist_ok=False)
    json_rel = f"{dynamic_dir}/generated.json"
    text_rel = f"{dynamic_dir}/raw.txt"
    link_rel = f"linked_{token}.txt"
    with open(os.path.join(root, json_rel), "wb") as f:
        f.write(dynamic_json)
    with open(os.path.join(root, text_rel), "wb") as f:
        f.write(dynamic_text)
    os.symlink(text_rel, os.path.join(root, link_rel))
    os.symlink(".", os.path.join(root, dynamic_dir, "relative_loop"))

    EXPECTED_FILES = {
        "main.json": b'{"app": "v1.0", "debug": true}\n',
        "secrets.txt": b"super_secret_key_123\n",
        json_rel: dynamic_json,
        text_rel: dynamic_text,
        link_rel: dynamic_text,
    }

    hue = secrets.randbelow(360)
    tmp_video = f"/tmp/config_history_{token}.mp4"
    subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-y",
            "-f", "lavfi",
            "-i", "testsrc2=size=160x120:rate=12:duration=2",
            "-vf", f"hue=h={hue}",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            tmp_video,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    history_object = [{
        "timestamp": secrets.randbelow(2_000_000_000),
        "files": [f"old-{token}.json", f"archive-{secrets.token_hex(4)}.txt"],
    }]
    EXPECTED_HISTORY = json.dumps(
        history_object, separators=(",", ":")
    ).encode()
    with open(tmp_video, "ab") as f:
        f.write(b"CFGB" + zlib.compress(EXPECTED_HISTORY))
    os.replace(tmp_video, "/app/config_history.mp4")

    random_valid = secrets.choice([1, 3, 6, 13, 17, 21])
    random_out_of_range = 100 + secrets.randbelow(500)
    FRAME_NUMBERS = [10, random_valid, random_out_of_range]


def start_submitted_server():
    assert os.path.isfile(SERVER), f"Missing required executable: {SERVER}"
    mode = os.stat(SERVER).st_mode
    assert mode & stat.S_IXUSR, f"{SERVER} is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SERVER} is not a compiled ELF executable"

    proc = subprocess.Popen(
        [SERVER],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None and not listener_pids(PORT):
            pytest.fail(f"Submitted server exited with status {proc.returncode}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Submitted executable did not listen on {HOST}:{PORT}")


stop_existing_server()
build_runtime_fixture()
SERVER_PROCESS = start_submitted_server()


def send_command(cmd: str) -> bytes:
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.settimeout(8)
            s.sendall(cmd.encode("utf-8"))
            data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            return data
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail(f"Timeout while waiting for response to command: {cmd.strip()}")
    except Exception as e:
        pytest.fail(f"Error communicating with server: {e}")


def test_backup_command():
    raw_response = send_command("BACKUP\n")
    assert raw_response, "Received empty response for BACKUP command"

    try:
        decompressed = zlib.decompress(raw_response)
    except zlib.error as e:
        pytest.fail(f"Failed to zlib decompress BACKUP response: {e}")

    offset = 0
    files = {}
    while offset < len(decompressed):
        if offset + 2 > len(decompressed):
            pytest.fail("Truncated archive: missing path length")
        path_len = struct.unpack_from("<H", decompressed, offset)[0]
        offset += 2

        if offset + path_len > len(decompressed):
            pytest.fail("Truncated archive: missing path string")
        try:
            path = decompressed[offset:offset + path_len].decode("utf-8")
        except UnicodeDecodeError as e:
            pytest.fail(f"Archive path is not UTF-8: {e}")
        offset += path_len

        if offset + 4 > len(decompressed):
            pytest.fail("Truncated archive: missing file size")
        file_size = struct.unpack_from("<I", decompressed, offset)[0]
        offset += 4

        if offset + file_size > len(decompressed):
            pytest.fail("Truncated archive: missing file content")
        content = decompressed[offset:offset + file_size]
        offset += file_size

        normalized = path.lstrip("./")
        assert normalized not in files, f"Duplicate archive path: {normalized}"
        files[normalized] = content

    for expected_path, expected_content in EXPECTED_FILES.items():
        assert expected_path in files, f"Expected file {expected_path} missing from BACKUP archive"
        assert files[expected_path] == expected_content, f"Content mismatch for {expected_path}"

    assert len(files) == len(EXPECTED_FILES), f"Archive contains unexpected files: {list(files.keys())}"


def test_history_command():
    raw_response = send_command("HISTORY\n")
    assert raw_response.strip() == EXPECTED_HISTORY, \
        f"HISTORY command returned unexpected data: {raw_response!r}"


def expected_frame_hash(n):
    cmd = [
        "ffmpeg", "-i", "/app/config_history.mp4",
        "-vf", f"select='eq(n\\,{n})'",
        "-vframes", "1",
        "-f", "image2pipe",
        "-vcodec", "ppm", "-",
    ]
    try:
        result = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=15
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f"Failed to derive frame {n} truth data with ffmpeg: {e}")
    return hashlib.sha256(result.stdout).hexdigest()


def test_frame_hash_command():
    for n in FRAME_NUMBERS:
        expected_hash = expected_frame_hash(n)
        raw_response = send_command(f"FRAME_HASH {n}\n")
        try:
            actual_hash = raw_response.decode("ascii").strip()
        except UnicodeDecodeError:
            pytest.fail(f"FRAME_HASH {n} did not return an ASCII hash")
        assert actual_hash.lower() == expected_hash.lower(), \
            f"FRAME_HASH {n} returned {actual_hash}, expected {expected_hash}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
