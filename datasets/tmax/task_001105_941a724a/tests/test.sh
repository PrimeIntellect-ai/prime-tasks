#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import signal
import socket
import subprocess
import tempfile
import time


def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    address, port = local.rsplit(":", 1)
                    if int(port, 16) != 9090 or state != "0A":
                        continue
                    # Require the IPv4 loopback address requested by the task.
                    if table.endswith("tcp") and address != "0100007F":
                        continue
                    found.add(inode)
        except FileNotFoundError:
            pass
    return found


def wait_for_listener(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_inodes():
            return
        time.sleep(0.05)
    raise AssertionError("No server listening on 127.0.0.1:9090")


def kill_listener():
    inodes = listener_inodes()
    if not inodes:
        return
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Could not stop existing port 9090 listener"


def get_frames():
    paths = sorted(glob.glob("/home/user/frames/frame_*.raw"))
    expected_paths = [f"/home/user/frames/frame_{i:03d}.raw" for i in range(1, 101)]
    assert paths == expected_paths, "Frame set or naming is incorrect"
    frames = []
    for i, path in enumerate(expected_paths, 1):
        assert os.path.isfile(path), f"Missing frame file: {path}"
        with open(path, "rb") as f:
            data = f.read()
        assert len(data) == 4096, f"Frame {i} has incorrect size {len(data)}, expected 4096"
        frames.append(data)
    return frames


def compute_ground_truth(frames):
    features = []
    total = 0
    total_sq = 0
    count = 0
    for data in frames:
        feat = []
        for by in range(8):
            for bx in range(8):
                block_sum = 0
                for y in range(8):
                    start = (by * 8 + y) * 64 + bx * 8
                    block_sum += sum(data[start:start + 8])
                feat.append(block_sum // 64)
        features.append(feat)
        total += sum(data)
        total_sq += sum(v * v for v in data)
        count += len(data)

    mean = total / count
    variance = max(0.0, total_sq / count - mean * mean)
    std_dev = math.sqrt(variance)
    margin = 1.96 * std_dev / math.sqrt(count)
    return features, f"{mean - margin:.2f}", f"{mean + margin:.2f}"


def get_top_3_similar(features, query_idx):
    distances = []
    query = features[query_idx]
    for i, feat in enumerate(features):
        if i == query_idx:
            continue
        distance = sum((a - b) ** 2 for a, b in zip(query, feat))
        distances.append((distance, i + 1))
    distances.sort()
    return [item[1] for item in distances[:3]]


def query_server(q):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3.0)
        s.connect(("127.0.0.1", 9090))
        s.sendall(f"{q:03d}\n".encode())
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode("utf-8")


def check_server(frames):
    features, expected_low, expected_high = compute_ground_truth(frames)
    for q in range(1, 101):
        response = query_server(q)
        match = re.match(
            r"^SIMILAR=(\d{3}),(\d{3}),(\d{3}) CI=\[(\d+\.\d{2}),(\d+\.\d{2})\]\n$",
            response,
        )
        assert match is not None, f"Server response format invalid: {response!r}"
        actual = [int(match.group(1)), int(match.group(2)), int(match.group(3))]
        expected = get_top_3_similar(features, q - 1)
        assert actual == expected, f"Similarity mismatch for query {q}. Expected {expected}, got {actual}"
        assert match.group(4) == expected_low and match.group(5) == expected_high, (
            f"CI mismatch for query {q}. Expected [{expected_low},{expected_high}], "
            f"got [{match.group(4)},{match.group(5)}]"
        )


def test_complete_pipeline_and_c_server():
    script = "/home/user/run_pipeline.sh"
    source = "/home/user/server.c"
    assert os.path.isfile(script), "run_pipeline.sh not found"
    assert os.access(script, os.X_OK), "run_pipeline.sh is not executable"
    assert os.path.isfile(source), "server.c not found"

    # Independently decode the supplied video to establish the required frame bytes.
    with tempfile.TemporaryDirectory() as expected_dir:
        subprocess.run([
            "ffmpeg", "-v", "error", "-i", "/app/experiment.mp4",
            "-vf", "scale=64:64", "-pix_fmt", "gray", "-c:v", "rawvideo",
            "-f", "image2", os.path.join(expected_dir, "frame_%03d.raw")
        ], check=True, timeout=30)
        expected_files = sorted(glob.glob(os.path.join(expected_dir, "frame_*.raw")))
        assert len(expected_files) == 100, "Reference video did not decode to 100 frames"
        expected_frames = [open(path, "rb").read() for path in expected_files]

        kill_listener()
        subprocess.run(["rm", "-rf", "/home/user/frames"], check=True)
        proc = subprocess.Popen(
            [script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        try:
            assert proc.wait(timeout=30) == 0, "run_pipeline.sh failed"
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            raise AssertionError("run_pipeline.sh did not finish after starting the background server")

        actual_frames = get_frames()
        assert actual_frames == expected_frames, "Extracted frames do not match /app/experiment.mp4"
        wait_for_listener()
        kill_listener()

        # Compile the submitted C implementation itself, rather than trusting an
        # unrelated process left on the expected port.
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", "/tmp/verified_server", "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert compile_result.returncode == 0, f"server.c failed to compile:\n{compile_result.stderr}"

        # Exercise the compiled C server on unpredictable frame contents so fixed
        # answers for the shipped video cannot satisfy the behavioral checks.
        mutated = []
        for i, original in enumerate(expected_frames, 1):
            data = bytearray(original)
            randomness = os.urandom(96)
            for j, value in enumerate(randomness):
                pos = (j * 43 + i * 97) % 4096
                data[pos] = value
            data = bytes(data)
            mutated.append(data)
            with open(f"/home/user/frames/frame_{i:03d}.raw", "wb") as f:
                f.write(data)

        server = subprocess.Popen(
            ["/tmp/verified_server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            wait_for_listener()
            check_server(mutated)
        finally:
            kill_listener()
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    server.kill()
            # Leave the requested extracted artifacts intact after verification.
            for i, data in enumerate(expected_frames, 1):
                with open(f"/home/user/frames/frame_{i:03d}.raw", "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
