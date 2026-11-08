#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import signal
import socket
import subprocess
import tempfile
import time

PROXY_SRC = "/home/user/provision_cache_proxy.cpp"
PROXY_BIN = "/home/user/provision_cache_proxy"
WORKER_BIN = "/app/provision_worker"
GIT_DIR = "/home/user/config.git"
HOOK = os.path.join(GIT_DIR, "hooks", "post-receive")
HOST = "127.0.0.1"
PORT = 8080
NUM_REQUESTS = 100
TARGET_TIME = 66.0


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def test_proxy_binary_exists():
    assert os.path.isfile(PROXY_SRC), f"Proxy source not found at {PROXY_SRC}"
    assert os.path.getsize(PROXY_SRC) > 0, "Proxy source is empty"
    assert os.path.isfile(PROXY_BIN), f"Proxy binary not found at {PROXY_BIN}"
    assert os.access(PROXY_BIN, os.X_OK), f"Proxy binary at {PROXY_BIN} is not executable"
    with open(PROXY_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Proxy binary is not an ELF executable"
    with open(PROXY_SRC, "r", errors="ignore") as f:
        source = f.read()
    assert "/app/provision_worker" in source, "Proxy source does not supervise /app/provision_worker"
    compiled = "/tmp/provision_cache_proxy.recompiled"
    run(["g++", "-std=c++17", "-O2", "-pthread", PROXY_SRC, "-o", compiled],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_git_repo_exists():
    assert os.path.isdir(GIT_DIR), f"Bare Git repository not found at {GIT_DIR}"
    assert os.path.isdir(os.path.join(GIT_DIR, "objects")), f"{GIT_DIR} does not look like a bare Git repository"
    result = subprocess.check_output(
        ["git", "--git-dir", GIT_DIR, "rev-parse", "--is-bare-repository"], text=True
    ).strip()
    assert result == "true", f"{GIT_DIR} is not a bare Git repository"
    assert os.path.isfile(HOOK), "post-receive hook is missing"
    assert os.access(HOOK, os.X_OK), "post-receive hook is not executable"


def stop_existing_listener():
    # Remove any service left running by the agent so the submitted executable,
    # rather than an unrelated listener, must bind and answer the tests.
    wanted = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if local.endswith(":1F90") and state == "0A":
                    wanted.add(fields[9])
    except OSError:
        return
    if not wanted:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (OSError, ProcessLookupError):
            pass
    time.sleep(0.5)


def wait_for_proxy(proc):
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.25):
                return
        except OSError:
            if proc.poll() is not None:
                raise AssertionError(f"Proxy exited during startup with status {proc.returncode}")
            time.sleep(0.1)
    raise AssertionError("Proxy did not listen on 127.0.0.1:8080")


def request(payload, timeout=5):
    try:
        with socket.create_connection((HOST, PORT), timeout=timeout) as s:
            s.settimeout(timeout)
            s.sendall(payload)
            try:
                s.shutdown(socket.SHUT_WR)
            except OSError:
                pass
            chunks = []
            while sum(map(len, chunks)) < 65536:
                try:
                    part = s.recv(4096)
                except socket.timeout:
                    break
                if not part:
                    break
                chunks.append(part)
                if b"\n" in part:
                    break
            return b"".join(chunks)
    except OSError:
        return None


def parse_response(data):
    assert data is not None, "Proxy request failed"
    assert data.strip(), "Proxy returned an empty response"
    try:
        return json.loads(data.decode("utf-8").strip())
    except Exception as exc:
        raise AssertionError(f"Proxy returned invalid JSON: {data!r}: {exc}")


def worker_result():
    start = time.monotonic()
    completed = subprocess.run(
        [WORKER_BIN, GIT_DIR], check=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    elapsed = time.monotonic() - start
    return json.loads(completed.stdout.strip()), elapsed


def create_initial_commit():
    work = tempfile.mkdtemp(prefix="proxy-config-")
    run(["git", "init", work], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    run(["git", "-C", work, "config", "user.email", "verifier@example.invalid"])
    run(["git", "-C", work, "config", "user.name", "Verifier"])
    with open(os.path.join(work, "config.txt"), "w") as f:
        f.write("version=one\n")
    run(["git", "-C", work, "add", "config.txt"])
    run(["git", "-C", work, "commit", "-m", "initial"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    run(["git", "--git-dir", GIT_DIR, "symbolic-ref", "HEAD", "refs/heads/master"])
    run(["git", "-C", work, "push", "--force", GIT_DIR, "HEAD:refs/heads/master"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return work


def test_proxy_behavior_performance_hook_and_routing():
    work = create_initial_commit()
    expected_initial, baseline_time = worker_result()

    stop_existing_listener()
    proc = subprocess.Popen([PROXY_BIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_proxy(proc)

        warm = parse_response(request((GIT_DIR + "\n").encode()))
        assert warm == expected_initial, f"Warm-up response {warm!r} does not match worker output {expected_initial!r}"

        invalid_raw = request(b"this-is-not-a-valid-repository-request\n")
        assert invalid_raw is not None and invalid_raw.strip(), "Invalid request received no drop-bucket response"
        assert invalid_raw.strip() != json.dumps(expected_initial).encode(), "Invalid request was handled as a valid provisioning request"
        invalid_text = invalid_raw.decode("utf-8", errors="replace").lower()
        assert any(word in invalid_text for word in ("drop", "invalid", "reject", "default")), \
            f"Invalid request was not routed to a recognizable default drop bucket: {invalid_raw!r}"

        start = time.monotonic()
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            futures = [executor.submit(request, (GIT_DIR + "\n").encode()) for _ in range(NUM_REQUESTS)]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]
        total_time = time.monotonic() - start

        successful_requests = [r for r in results if r is not None]
        assert len(successful_requests) == NUM_REQUESTS, \
            f"Only {len(successful_requests)}/{NUM_REQUESTS} requests succeeded"
        parsed = [parse_response(r) for r in results]
        assert all(item == expected_initial for item in parsed), "One or more proxy responses did not match provision_worker output"

        derived_speed_target = baseline_time * NUM_REQUESTS / 3.0
        assert total_time < TARGET_TIME, \
            f"Performance test failed: took {total_time:.2f}s, target is < {TARGET_TIME}s"
        assert total_time < derived_speed_target, \
            f"Speedup was below 3.0x: proxy took {total_time:.2f}s; measured sequential estimate was {baseline_time * NUM_REQUESTS:.2f}s"

        old_commit = expected_initial.get("commit")
        with open(os.path.join(work, "config.txt"), "w") as f:
            f.write("version=two\n")
        run(["git", "-C", work, "add", "config.txt"])
        run(["git", "-C", work, "commit", "-m", "update"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        run(["git", "-C", work, "push", GIT_DIR, "HEAD:refs/heads/master"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        expected_updated, _ = worker_result()
        assert expected_updated.get("commit") != old_commit, "Test push did not change the repository commit"

        deadline = time.time() + 10
        last = None
        while time.time() < deadline:
            last = parse_response(request((GIT_DIR + "\n").encode()))
            if last == expected_updated:
                break
            time.sleep(0.2)
        assert last == expected_updated, \
            f"Cache was not invalidated after post-receive hook; got {last!r}, expected {expected_updated!r}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
