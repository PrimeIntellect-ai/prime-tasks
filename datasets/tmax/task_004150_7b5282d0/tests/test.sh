#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import signal
import socket
import subprocess
import time
import uuid

import pytest


@pytest.fixture(scope="session", autouse=True)
def setup_truth_frames():
    """Generate ground truth frames using ffmpeg."""
    truth_dir = "/tmp/truth_frames"
    os.makedirs(truth_dir, exist_ok=True)

    cmd = [
        "ffmpeg", "-y", "-i", "/app/cctv.mp4",
        "-r", "1", "-vframes", "30",
        "-f", "image2", "-vcodec", "pgm",
        f"{truth_dir}/truth_frame_%03d.pgm",
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    yield truth_dir


def fetch_frame(filename, timeout=5.0):
    """Fetch one frame from the TCP service."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect(("127.0.0.1", 8888))
        s.sendall(f"FETCH {filename}\n".encode("utf-8"))

        chunks = []
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def test_spool_directory_empty():
    """Check that /home/user/spool/ exists and is empty."""
    spool_dir = "/home/user/spool"
    assert os.path.isdir(spool_dir), f"Directory {spool_dir} does not exist."
    files = os.listdir(spool_dir)
    assert len(files) == 0, f"Directory {spool_dir} is not empty. Found: {files}"


def test_archive_file_exists_and_compressed(setup_truth_frames):
    """Check that the archive exists, is nonempty, and is compressed."""
    archive_path = "/home/user/video_archive.bin"
    assert os.path.isfile(archive_path), f"Archive file {archive_path} does not exist."

    archive_size = os.path.getsize(archive_path)
    assert archive_size > 0, "Archive is empty."

    truth_files = glob.glob(f"{setup_truth_frames}/truth_frame_*.pgm")
    assert len(truth_files) > 0, "No truth frames were generated."
    total_raw_size = sum(os.path.getsize(f) for f in truth_files)

    assert archive_size <= total_raw_size * 0.9, (
        f"Archive size ({archive_size} bytes) is not at least 10% smaller than "
        f"total raw size ({total_raw_size} bytes)."
    )


def test_tcp_fetch_frame_007(setup_truth_frames):
    response = fetch_frame("frame_007.pgm")
    with open(f"{setup_truth_frames}/truth_frame_007.pgm", "rb") as f:
        truth_data = f.read()
    assert response == truth_data, "Fetched frame_007.pgm does not match ground truth byte-for-byte."


def test_tcp_fetch_frame_029(setup_truth_frames):
    response = fetch_frame("frame_029.pgm")
    with open(f"{setup_truth_frames}/truth_frame_029.pgm", "rb") as f:
        truth_data = f.read()
    assert response == truth_data, "Fetched frame_029.pgm does not match ground truth byte-for-byte."


def test_all_extracted_frames_are_retrievable(setup_truth_frames):
    """Ensure the archive contains the complete extraction, not a fixed subset."""
    for number in range(1, 31):
        name = f"frame_{number:03d}.pgm"
        with open(f"{setup_truth_frames}/truth_frame_{number:03d}.pgm", "rb") as f:
            expected = f.read()
        assert fetch_frame(name) == expected, f"Fetched {name} does not match ground truth."


def test_tcp_fetch_missing_frame():
    response = fetch_frame("frame_999.pgm")
    assert response == b"ERROR\n", f"Expected 'ERROR\\n' for missing frame, got {response!r}"


def listener_pids(port):
    """Find processes owning listening IPv4 TCP sockets on the given port."""
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_port = int(fields[1].split(":")[1], 16)
            state = fields[3]
            if local_port == port and state == "0A":
                inodes.add(fields[9])

    owners = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit("/", 1)[1])
        for fd in glob.glob(f"{proc_dir}/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(pid)
                break
    return owners


def test_live_inotify_archiving_compression_and_persistence():
    """Inject unpredictable frames, require deletion, compression, and archive-backed restart retrieval."""
    spool = "/home/user/spool"
    archive = "/home/user/video_archive.bin"
    assert listener_pids(8888), "No process is listening on TCP port 8888."

    baseline_size = os.path.getsize(archive)
    nonce = uuid.uuid4().hex
    probes = {}

    # Valid binary PGM files with verifier-selected names and content. Long runs
    # make the expected RLE result much smaller than the raw inputs.
    for index in range(3):
        name = f"frame_probe_{nonce}_{index}.pgm"
        value = os.urandom(1)
        data = b"P5\n256 256\n255\n" + value * (256 * 256)
        path = os.path.join(spool, name)
        with open(path, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        probes[name] = data

    deadline = time.time() + 15
    while time.time() < deadline:
        if all(not os.path.exists(os.path.join(spool, name)) for name in probes):
            break
        time.sleep(0.1)
    remaining = [name for name in probes if os.path.exists(os.path.join(spool, name))]
    assert not remaining, f"Daemon did not delete newly closed spool files: {remaining}"

    for name, expected in probes.items():
        assert fetch_frame(name) == expected, f"Dynamically archived frame {name} was not returned exactly."

    grown_size = os.path.getsize(archive) - baseline_size
    total_probe_size = sum(map(len, probes.values()))
    assert grown_size > 0, "Archive did not grow after new frames were archived."
    assert grown_size < total_probe_size, (
        f"Archive grew by {grown_size} bytes for {total_probe_size} bytes of highly RLE-compressible input."
    )

    # Restart the actual listener executable. Retrieval must still work after
    # memory is discarded, proving that responses come from the archive.
    pids = listener_pids(8888)
    assert pids, "Could not identify the daemon process."
    pid = min(pids)
    exe = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "TCP service is not a compiled native daemon."
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        old_args = [x.decode("utf-8", "surrogateescape") for x in f.read().split(b"\0") if x]
    restart_args = [exe] + old_args[1:]

    for owner in pids:
        try:
            os.kill(owner, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(8888):
        time.sleep(0.05)
    for owner in listener_pids(8888):
        try:
            os.kill(owner, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8888):
        time.sleep(0.05)
    assert not listener_pids(8888), "Old daemon did not stop for persistence test."

    subprocess.Popen(
        restart_args,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 10
    while time.time() < deadline and not listener_pids(8888):
        time.sleep(0.1)
    assert listener_pids(8888), "Daemon did not resume listening after restart."

    for name, expected in probes.items():
        assert fetch_frame(name) == expected, (
            f"Frame {name} was not recoverable from the archive after daemon restart."
        )

    missing = f"frame_missing_{uuid.uuid4().hex}.pgm"
    assert fetch_frame(missing) == b"ERROR\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
