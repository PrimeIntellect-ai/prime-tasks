#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import glob
import heapq
import json
import os
import secrets
import shutil
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

BIN = "/tmp/submission_server"
VIDEO = "/app/backup_topology.mp4"
BASE = "http://127.0.0.1:8080"


def compile_submission():
    roots = ["/app", "/home/user", "/root", "/tmp"]
    sources = []
    for root in roots:
        for path in glob.glob(root + "/**/*.c", recursive=True):
            if path.startswith("/tmp/test"):
                continue
            if os.path.isfile(path):
                sources.append(path)

    main_sources = []
    for path in sources:
        try:
            text = open(path, "r", errors="ignore").read()
        except OSError:
            continue
        if "main" in text:
            main_sources.append(path)

    assert main_sources, "No C source file containing a main function was found"

    attempts = []
    for main in main_sources:
        attempts.append([main])
        directory_sources = sorted(
            p for p in sources if os.path.dirname(p) == os.path.dirname(main)
        )
        if directory_sources != [main]:
            attempts.append(directory_sources)

    errors = []
    for files in attempts:
        cmd = ["gcc", "-O2", "-std=gnu11", "-pthread", "-I" + os.path.dirname(files[0]),
               *files, "-o", BIN, "-lm"]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            os.chmod(BIN, 0o755)
            return
        errors.append(result.stderr[-2000:])

    pytest.fail("Could not compile the submitted C program:\n" + "\n---\n".join(errors))


def listener_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(pid)
                break
    return owners


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def http_get(path, timeout=5):
    try:
        with urllib.request.urlopen(BASE + path, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")


def start_server():
    stop_server()
    proc = subprocess.Popen(
        [BIN], cwd="/app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            http_get("/restore_path?source=5&dest=50", timeout=0.5)
            break
        except Exception:
            if proc.poll() is not None and not listener_pids():
                pytest.fail(f"Compiled C server exited with status {proc.returncode}")
            time.sleep(0.1)
    else:
        pytest.fail("Server is not running or not reachable at 127.0.0.1:8080")

    owners = listener_pids()
    assert owners, "No process is listening on 127.0.0.1:8080"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", BIN)
        for pid in owners
    ), "Port 8080 is not served by the C executable compiled from the submission"
    return proc


def parse_json(body):
    try:
        return json.loads(body)
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {body}")


def run_original_assertions():
    status, body = http_get("/restore_path?source=5&dest=50")
    assert status == 200, f"Expected status code 200, got {status}. Response: {body}"
    data = parse_json(body)
    assert "path" in data, f"Missing 'path' in response: {data}"
    assert "total_latency" in data, f"Missing 'total_latency' in response: {data}"
    assert data["path"] == [5, 12, 50], f"Expected path [5, 12, 50], got {data['path']}"
    assert data["total_latency"] == 30, f"Expected total_latency 30, got {data['total_latency']}"

    status, body = http_get("/restore_path?source=12&dest=8")
    assert status == 200, f"Expected status code 200, got {status}. Response: {body}"
    data = parse_json(body)
    assert "path" in data, f"Missing 'path' in response: {data}"
    assert "total_latency" in data, f"Missing 'total_latency' in response: {data}"
    assert data["path"] == [12, 8], f"Expected path [12, 8], got {data['path']}"
    assert data["total_latency"] == 5, f"Expected total_latency 5, got {data['total_latency']}"

    status, body = http_get("/restore_path?source=5&dest=99")
    assert status == 404, f"Expected status code 404 for no path, got {status}. Response: {body}"
    data = parse_json(body)
    assert "error" in data, f"Missing 'error' key in 404 response: {data}"


def make_challenge_video(path):
    rng = secrets.SystemRandom()
    nodes = rng.sample(range(20, 231), 12)
    left, right = nodes[:8], nodes[8:]
    edges = []

    for group in (left, right):
        for i, source in enumerate(group):
            edges.append((source, group[(i + 1) % len(group)], rng.randint(3, 180)))
    edges.append((rng.choice(left), rng.choice(right), rng.randint(3, 180)))
    while len(edges) < 50:
        group = left if rng.randrange(4) else right
        source, dest = rng.sample(group, 2)
        edges.append((source, dest, rng.randint(3, 180)))
    rng.shuffle(edges)

    raw = "/tmp/challenge.rgb"
    with open(raw, "wb") as output:
        for edge in edges:
            output.write(bytes(edge) * (64 * 64))

    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo",
        "-pixel_format", "rgb24", "-video_size", "64x64", "-framerate", "1",
        "-i", raw, "-frames:v", "50", "-c:v", "libx264rgb", "-crf", "0",
        "-preset", "ultrafast", path
    ], check=True)


def decode_video(path):
    result = subprocess.run([
        "ffmpeg", "-loglevel", "error", "-i", path,
        "-vf", "crop=1:1:0:0", "-frames:v", "50",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ], check=True, stdout=subprocess.PIPE)
    assert len(result.stdout) == 150, "Challenge video did not decode to exactly 50 frames"
    return [tuple(result.stdout[i:i + 3]) for i in range(0, 150, 3)]


def shortest(edges, source, dest):
    adjacency = {}
    for u, v, weight in edges:
        adjacency.setdefault(u, []).append((v, weight))
    distance = {source: 0}
    queue = [(0, source)]
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distance[node]:
            continue
        if node == dest:
            return cost
        for nxt, weight in adjacency.get(node, []):
            new_cost = cost + weight
            if new_cost < distance.get(nxt, 10**30):
                distance[nxt] = new_cost
                heapq.heappush(queue, (new_cost, nxt))
    return None


def validate_challenge_server(edges):
    nodes = sorted({u for u, _, _ in edges} | {v for _, v, _ in edges})
    minimum_edge = {}
    for u, v, weight in edges:
        minimum_edge[(u, v)] = min(weight, minimum_edge.get((u, v), weight))

    pairs = [(u, v) for u in nodes for v in nodes if u != v]
    secrets.SystemRandom().shuffle(pairs)
    for source, dest in pairs:
        expected = shortest(edges, source, dest)
        status, body = http_get(f"/restore_path?source={source}&dest={dest}")
        data = parse_json(body)
        if expected is None:
            assert status == 404, (
                f"Expected 404 for challenge query {source}->{dest}, got {status}: {body}"
            )
            assert data == {"error": "no path"}, f"Incorrect no-path response: {data}"
            continue

        assert status == 200, (
            f"Expected 200 for challenge query {source}->{dest}, got {status}: {body}"
        )
        assert "path" in data and "total_latency" in data, f"Incomplete response: {data}"
        path = data["path"]
        assert isinstance(path, list) and path and path[0] == source and path[-1] == dest, (
            f"Invalid path endpoints for {source}->{dest}: {path}"
        )
        try:
            actual_cost = sum(minimum_edge[(a, b)] for a, b in zip(path, path[1:]))
        except KeyError as error:
            pytest.fail(f"Returned path uses a nonexistent directed edge: {error.args[0]}")
        assert actual_cost == expected, f"Returned path is not shortest: {path}"
        assert data["total_latency"] == expected, (
            f"Expected latency {expected}, got {data['total_latency']} for {source}->{dest}"
        )


def test_complete_submission():
    compile_submission()
    assert os.path.isfile(VIDEO), f"Missing required video artifact: {VIDEO}"

    proc = None
    backup = "/tmp/original_backup_topology.mp4"
    try:
        proc = start_server()
        run_original_assertions()
        stop_server()
        proc = None

        shutil.copy2(VIDEO, backup)
        try:
            make_challenge_video(VIDEO)
            challenge_edges = decode_video(VIDEO)
            proc = start_server()
            validate_challenge_server(challenge_edges)
        finally:
            stop_server()
            proc = None
            if os.path.exists(backup):
                shutil.copy2(backup, VIDEO)
    finally:
        stop_server()
        if os.path.exists(backup):
            shutil.copy2(backup, VIDEO)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
