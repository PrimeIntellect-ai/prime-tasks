#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_repo_bin_exists():
    path = "/home/user/repo.bin"
    assert os.path.isfile(path), f"The archive file {path} does not exist."


def test_repo_bin_size():
    path = "/home/user/repo.bin"
    assert os.path.isfile(path), f"The archive file {path} does not exist."
    size = os.path.getsize(path)
    threshold = 2500000
    assert size <= threshold, f"Archive size is {size} bytes, which exceeds the threshold of {threshold} bytes. Compression may have failed or not been applied."
    assert size > 0, "The archive is empty."


def test_incoming_directory_empty():
    path = "/home/user/incoming"
    assert os.path.isdir(path), f"Incoming directory {path} is missing."
    files = os.listdir(path)
    assert len(files) == 0, f"Incoming directory is not empty. Unprocessed files: {files}"


def test_cmake_fixed():
    path = "/app/vendor/snappy-1.1.10/CMakeLists.txt"
    if os.path.isfile(path):
        with open(path, "r") as f:
            content = f.read()
        assert "set(CMAKE_CXX_STANDARD 98)" not in content, "The CMakeLists.txt file still contains the C++98 perturbation."


def test_snappy_installed():
    paths = [
        "/home/user/local/lib/libsnappy.a",
        "/home/user/local/lib/libsnappy.so",
        "/home/user/local/lib64/libsnappy.a",
        "/home/user/local/lib64/libsnappy.so",
    ]
    assert any(os.path.isfile(p) for p in paths), "Snappy library does not appear to be installed in /home/user/local/lib or lib64."


def test_archiver_source_exists():
    path = "/home/user/archiver.cpp"
    assert os.path.isfile(path), f"The required source file {path} does not exist."
    assert os.path.getsize(path) > 0, f"The required source file {path} is empty."
TEST_EOF

cat << 'PY_EOF' > /tmp/check_archive.py
import os
import struct
import sys


def snappy_uncompress(src):
    pos = 0
    shift = 0
    expected = 0
    while True:
        if pos >= len(src) or shift > 63:
            raise ValueError("invalid Snappy length varint")
        b = src[pos]
        pos += 1
        expected |= (b & 0x7f) << shift
        if not (b & 0x80):
            break
        shift += 7

    out = bytearray()
    while pos < len(src):
        tag = src[pos]
        pos += 1
        kind = tag & 3
        if kind == 0:
            n = tag >> 2
            if n < 60:
                length = n + 1
            else:
                extra = n - 59
                if extra < 1 or extra > 4 or pos + extra > len(src):
                    raise ValueError("invalid Snappy literal length")
                length = int.from_bytes(src[pos:pos + extra], "little") + 1
                pos += extra
            if pos + length > len(src):
                raise ValueError("truncated Snappy literal")
            out.extend(src[pos:pos + length])
            pos += length
        else:
            if kind == 1:
                length = 4 + ((tag >> 2) & 7)
                if pos >= len(src):
                    raise ValueError("truncated Snappy copy")
                offset = ((tag & 0xe0) << 3) | src[pos]
                pos += 1
            elif kind == 2:
                length = 1 + (tag >> 2)
                if pos + 2 > len(src):
                    raise ValueError("truncated Snappy copy")
                offset = int.from_bytes(src[pos:pos + 2], "little")
                pos += 2
            else:
                length = 1 + (tag >> 2)
                if pos + 4 > len(src):
                    raise ValueError("truncated Snappy copy")
                offset = int.from_bytes(src[pos:pos + 4], "little")
                pos += 4
            if offset <= 0 or offset > len(out):
                raise ValueError("invalid Snappy copy offset")
            for _ in range(length):
                out.append(out[-offset])
        if len(out) > expected:
            raise ValueError("Snappy output exceeds declared size")

    if len(out) != expected:
        raise ValueError("Snappy output has the wrong size")
    return bytes(out)


def read_archive(path):
    data = open(path, "rb").read()
    entries = []
    pos = 0
    while pos < len(data):
        end = data.find(b"\0", pos)
        if end < 0:
            raise ValueError("unterminated filename")
        raw_name = data[pos:end]
        if not raw_name:
            raise ValueError("empty filename")
        name = raw_name.decode("utf-8")
        pos = end + 1
        if pos + 8 > len(data):
            raise ValueError("truncated compressed-size header")
        compressed_size = struct.unpack_from("<Q", data, pos)[0]
        pos += 8
        if compressed_size == 0 or pos + compressed_size > len(data):
            raise ValueError("invalid compressed data size")
        payload = data[pos:pos + compressed_size]
        pos += compressed_size
        entries.append((name, snappy_uncompress(payload)))
    return entries


def check_original(path):
    entries = read_archive(path)
    expected_names = {f"dummy_{i}.bin" for i in range(1, 51)}
    assert len(entries) == 50, f"expected 50 archive entries, found {len(entries)}"
    names = [name for name, _ in entries]
    assert len(set(names)) == 50, "archive contains duplicate filenames"
    assert set(names) == expected_names, f"archive filenames are incorrect: {set(names) ^ expected_names}"
    for name, content in entries:
        assert len(content) == 1024 * 1024, f"{name} has the wrong decompressed size"
        assert not any(content), f"{name} did not decompress to the uploaded zero-filled binary"


def check_directory(path, expected_dir):
    expected = {}
    for name in os.listdir(expected_dir):
        with open(os.path.join(expected_dir, name), "rb") as f:
            expected[name] = f.read()
    entries = read_archive(path)
    assert len(entries) == len(expected), f"expected {len(expected)} entries, found {len(entries)}"
    actual = {}
    for name, content in entries:
        assert name not in actual, f"duplicate entry {name}"
        actual[name] = content
    assert set(actual) == set(expected), f"archive filenames differ: {set(actual) ^ set(expected)}"
    for name in expected:
        assert actual[name] == expected[name], f"decompressed contents for {name} are incorrect"


if sys.argv[1] == "original":
    check_original(sys.argv[2])
elif sys.argv[1] == "directory":
    check_directory(sys.argv[2], sys.argv[3])
else:
    raise SystemExit("unknown mode")
PY_EOF

run_extra_checks() {
    python3 /tmp/check_archive.py original /home/user/repo.bin || return 1

    local lib=""
    for candidate in \
        /home/user/local/lib/libsnappy.a \
        /home/user/local/lib/libsnappy.so \
        /home/user/local/lib64/libsnappy.a \
        /home/user/local/lib64/libsnappy.so; do
        if [ -f "$candidate" ]; then
            lib="$candidate"
            break
        fi
    done
    [ -n "$lib" ] || return 1

    local libdir
    libdir=$(dirname "$lib")
    g++ -std=c++11 -O2 -I/home/user/local/include /home/user/archiver.cpp "$lib" \
        -pthread -Wl,-rpath,"$libdir" -o /tmp/verifier_archiver || return 1
    [ -x /tmp/verifier_archiver ] || return 1

    # Stop a previously launched watcher so only the freshly compiled submitted
    # source can satisfy the behavioral test below.
    python3 - << 'PY'
import os
import signal

ancestors = set()
pid = os.getpid()
while pid > 1:
    ancestors.add(pid)
    try:
        with open(f"/proc/{pid}/stat") as f:
            pid = int(f.read().split()[3])
    except Exception:
        break

for item in os.listdir("/proc"):
    if not item.isdigit():
        continue
    pid = int(item)
    if pid in ancestors or pid <= 1:
        continue
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except Exception:
        exe = ""
    try:
        cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "ignore")
    except Exception:
        cmd = ""
    if exe.startswith("/home/user/") or "archiver" in cmd.lower():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
PY

    local backup=/tmp/repo.bin.pre_verifier
    rm -f "$backup"
    mv /home/user/repo.bin "$backup" || return 1
    rm -rf /home/user/incoming
    mkdir -p /home/user/incoming
    chmod 777 /home/user/incoming
    : > /home/user/repo.bin
    chmod 666 /home/user/repo.bin

    local status=0
    ARCHIVER=/tmp/verifier_archiver python3 - << 'PY' || status=$?
import fcntl
import os
import signal
import subprocess
import time

incoming = "/home/user/incoming"
repo = "/home/user/repo.bin"
expected = "/tmp/verifier_expected"
os.makedirs(expected, exist_ok=True)
for old in os.listdir(expected):
    os.unlink(os.path.join(expected, old))

samples = {
    "verify_alpha.bin": os.urandom(131071),
    "verify_beta.bin": (b"artifact-compression-check\0" * 9000) + os.urandom(257),
    "verify_gamma.bin": bytes(196613),
}
for name, content in samples.items():
    with open(os.path.join(expected, name), "wb") as f:
        f.write(content)

lock_file = open(repo, "r+b", buffering=0)
fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
proc = subprocess.Popen([os.environ["ARCHIVER"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    time.sleep(0.3)
    assert proc.poll() is None, "compiled archiver exited instead of continuously polling"

    io_before = 0
    try:
        for line in open(f"/proc/{proc.pid}/io"):
            if line.startswith("wchar:"):
                io_before = int(line.split()[1])
    except OSError:
        pass

    for name, content in samples.items():
        tmp = os.path.join("/tmp", ".upload_" + name)
        with open(tmp, "wb") as f:
            f.write(content)
        os.replace(tmp, os.path.join(incoming, name))

    time.sleep(1.0)
    assert os.path.getsize(repo) == 0, "archiver wrote to repo.bin without obtaining the exclusive flock"
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    deadline = time.time() + 30
    while time.time() < deadline:
        if not os.listdir(incoming) and os.path.getsize(repo) > 0:
            break
        assert proc.poll() is None, "compiled archiver exited before processing the files"
        time.sleep(0.1)
    assert not os.listdir(incoming), "compiled archiver did not remove all processed files"
    assert os.path.getsize(repo) > 0, "compiled archiver did not write an archive"

    io_after = io_before
    try:
        for line in open(f"/proc/{proc.pid}/io"):
            if line.startswith("wchar:"):
                io_after = int(line.split()[1])
    except OSError:
        pass
    assert io_after > io_before, "the freshly compiled archiver process did not write output"

    subprocess.run(["python3", "/tmp/check_archive.py", "directory", repo, expected], check=True)
finally:
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass
    lock_file.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
PY

    rm -f /home/user/repo.bin
    mv "$backup" /home/user/repo.bin
    rm -rf /home/user/incoming
    mkdir -p /home/user/incoming
    chmod 777 /home/user/incoming
    return "$status"
}

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && run_extra_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
