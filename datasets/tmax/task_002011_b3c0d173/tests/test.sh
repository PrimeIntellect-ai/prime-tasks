#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_archive_task.py
import hashlib
import os
import shutil
import socket
import subprocess
import tarfile
import time
import urllib.request

RAW_DIR = "/home/user/raw_logs"
ARCHIVE_DIR = "/home/user/archives"
SCRIPT = "/home/user/archive_logs.sh"
THRESHOLD = 1_500_000


def redis_value(key):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect(("127.0.0.1", 6379))
        key_b = key.encode()
        request = b"*2\r\n$3\r\nGET\r\n$" + str(len(key_b)).encode() + b"\r\n" + key_b + b"\r\n"
        s.sendall(request)
        header = b""
        while b"\r\n" not in header:
            chunk = s.recv(1)
            if not chunk:
                break
            header += chunk
        if header.startswith(b"$-1"):
            return None
        assert header.startswith(b"$"), "Unexpected Redis response"
        length = int(header[1:-2])
        data = b""
        while len(data) < length + 2:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data[:length].decode()


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_member(name):
    name = name.replace("\\", "/")
    while name.startswith("./"):
        name = name[2:]
    name = name.lstrip("/")
    parts = [part for part in name.split("/") if part not in ("", ".")]
    assert ".." not in parts, f"Unsafe archive member: {name}"
    prefix = ["home", "user", "raw_logs"]
    if parts[:3] == prefix:
        parts = parts[3:]
    return "/".join(parts)


def generate_logs():
    last_error = None
    for _ in range(20):
        try:
            request = urllib.request.Request("http://127.0.0.1:5000/generate", data=b"", method="POST")
            with urllib.request.urlopen(request, timeout=120) as response:
                assert response.status == 200
                return
        except Exception as exc:
            last_error = exc
            time.sleep(1)
    raise AssertionError(f"Could not generate logs: {last_error}")


def inspect_archive(archive, expected):
    if archive.endswith(".tar.xz"):
        command = ["xz", "-dc", archive]
    elif archive.endswith(".tar.zst"):
        command = ["zstd", "-q", "-dc", archive]
    else:
        raise AssertionError(f"Unsupported archive name: {archive}")

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    found = {}
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as tf:
            for member in tf:
                if member.isdir():
                    continue
                assert member.isreg(), f"Archive contains a non-regular member: {member.name}"
                relative = normalize_member(member.name)
                assert relative in expected, f"Unexpected archived file: {member.name}"
                assert relative not in found, f"Duplicate archived file: {relative}"
                source = tf.extractfile(member)
                assert source is not None
                digest = hashlib.sha256()
                size = 0
                while True:
                    chunk = source.read(1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    digest.update(chunk)
                found[relative] = (size, digest.hexdigest())
        process.stdout.close()
        stderr = process.stderr.read().decode(errors="replace")
        status = process.wait(timeout=30)
        assert status == 0, f"Archive decompression failed: {stderr}"
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()

    assert set(found) == set(expected), f"Archive contains {len(found)} expected logs, not {len(expected)}"
    for relative, metadata in expected.items():
        assert found[relative] == metadata, f"Archived content differs for {relative}"


def main():
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), f"Missing regular Bash script at {SCRIPT}"
    with open(SCRIPT, "rb") as f:
        script_data = f.read()
    assert script_data and b"\x00" not in script_data, "Archive script is empty or not a text script"
    subprocess.run(["bash", "-n", SCRIPT], check=True, timeout=30)

    shutil.rmtree(RAW_DIR, ignore_errors=True)
    shutil.rmtree(ARCHIVE_DIR, ignore_errors=True)
    os.makedirs(RAW_DIR, mode=0o777, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, mode=0o777, exist_ok=True)
    os.chmod(RAW_DIR, 0o777)
    os.chmod(ARCHIVE_DIR, 0o777)
    subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "FLUSHDB"], check=True, stdout=subprocess.DEVNULL)

    generate_logs()

    expected = {}
    for root, _, files in os.walk(RAW_DIR):
        for filename in files:
            if filename.endswith(".log"):
                path = os.path.join(root, filename)
                relative = os.path.relpath(path, RAW_DIR).replace(os.sep, "/")
                expected[relative] = (os.path.getsize(path), file_hash(path))
    assert len(expected) == 500, f"Generator produced {len(expected)} logs, expected 500"

    subprocess.run(["bash", SCRIPT], check=True, timeout=900)
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), f"Script no longer exists at {SCRIPT}"

    assert os.path.isdir(ARCHIVE_DIR), f"{ARCHIVE_DIR} does not exist"
    total_size = 0
    for root, _, files in os.walk(ARCHIVE_DIR):
        for filename in files:
            total_size += os.path.getsize(os.path.join(root, filename))
    assert total_size > 0, "Archive directory is empty; no archives were created"
    assert total_size <= THRESHOLD, f"Archive size {total_size} exceeds {THRESHOLD} bytes"
    assert total_size < THRESHOLD, f"Archive size must be strictly less than {THRESHOLD} bytes"

    candidates = [
        os.path.join(ARCHIVE_DIR, "master_archive.tar.xz"),
        os.path.join(ARCHIVE_DIR, "master_archive.tar.zst"),
    ]
    candidates = [path for path in candidates if os.path.isfile(path) and not os.path.islink(path)]
    assert len(candidates) == 1, "Exactly one master_archive.tar.xz or master_archive.tar.zst must exist"
    inspect_archive(candidates[0], expected)

    remaining_logs = []
    done = {}
    for root, _, files in os.walk(RAW_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(".log"):
                remaining_logs.append(path)
            if filename.endswith(".log.done"):
                relative = os.path.relpath(path[:-5], RAW_DIR).replace(os.sep, "/")
                done[relative] = path
    assert not remaining_logs, f"Found {len(remaining_logs)} unprocessed .log files"
    assert len(done) > 0, "No .log.done files found"
    assert set(done) == set(expected), f"Found {len(done)} renamed logs, expected {len(expected)}"

    for relative, done_path in done.items():
        assert os.path.isfile(done_path) and not os.path.islink(done_path), f"Invalid done file: {done_path}"
        assert (os.path.getsize(done_path), file_hash(done_path)) == expected[relative], f"Renamed log content changed: {relative}"
        original = os.path.join(RAW_DIR, *relative.split("/"))
        key = f"processed:{original}"
        assert redis_value(key) == "1", f"Expected Redis key {key} to equal 1"


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_archive_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
