#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import cv2
import time
import pwd
import signal
import socket
import secrets
import threading
import subprocess
import numpy as np

FAST = "/home/user/fast_analyzer.py"
LEGACY = "/home/user/legacy_analyzer.py"
VIDEO = "/app/server_monitor.mp4"
DEPLOY = "/home/user/deploy.sh"


def run_analyzer(script_path, timeout=120):
    start = time.perf_counter()
    result = subprocess.run(
        ["python3", script_path], capture_output=True, text=True, timeout=timeout
    )
    duration = time.perf_counter() - start
    assert result.returncode == 0, f"{script_path} failed: {result.stderr}"
    assert re.fullmatch(r"\s*\d+\s*", result.stdout), (
        f"{script_path} must output only one integer, got {result.stdout!r}"
    )
    return duration, int(result.stdout.strip())


def reference_count(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open generated test video {path}"
    count = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        if np.mean(frame) < 100.0:
            count += 1
    cap.release()
    assert frames > 0
    return count


def make_unpredictable_video(path, width, height, frame_count):
    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = np.random.default_rng(seed)
    writer = cv2.VideoWriter(
        path, cv2.VideoWriter_fourcc(*"mp4v"), 17.0, (width, height)
    )
    assert writer.isOpened(), "Failed to create behavioral-test video"
    dark_total = int(rng.integers(frame_count // 4, 3 * frame_count // 4))
    labels = np.array([1] * dark_total + [0] * (frame_count - dark_total))
    rng.shuffle(labels)
    for is_dark in labels:
        base = int(rng.integers(20, 70) if is_dark else rng.integers(145, 225))
        noise = rng.integers(-12, 13, size=(height, width, 3), dtype=np.int16)
        frame = np.clip(base + noise, 0, 255).astype(np.uint8)
        writer.write(frame)
    writer.release()


def test_fast_analyzer_speedup_and_correctness():
    assert os.path.isfile(FAST), f"{FAST} does not exist."
    assert os.path.isfile(LEGACY), f"{LEGACY} does not exist."

    trusted = "/tmp/trusted_legacy_analyzer.py"
    with open(trusted, "w") as f:
        f.write('''import cv2\nimport numpy as np\ncap=cv2.VideoCapture("/app/server_monitor.mp4")\nc=0\nwhile True:\n    ok, frame=cap.read()\n    if not ok: break\n    if np.mean(frame) < 100.0: c += 1\ncap.release()\nprint(c)\n''')

    legacy_time, legacy_ans = run_analyzer(LEGACY)
    trusted_time, trusted_ans = run_analyzer(trusted)
    fast_time, fast_ans = run_analyzer(FAST)

    assert legacy_ans == fast_ans, (
        f"Output mismatch: Legacy={legacy_ans}, Fast={fast_ans}"
    )
    assert trusted_ans == fast_ans, (
        f"Output mismatch: trusted reference={trusted_ans}, Fast={fast_ans}"
    )
    speedup = legacy_time / fast_time
    assert speedup >= 3.0, (
        f"Speedup is {speedup:.2f}x, which is less than the required 3.0x."
    )
    trusted_speedup = trusted_time / fast_time
    assert trusted_speedup >= 3.0, (
        f"Speedup against an unmodified baseline is {trusted_speedup:.2f}x, "
        "which is less than the required 3.0x."
    )


def test_fast_analyzer_on_unpredictable_videos():
    backup = "/tmp/server_monitor.original.mp4"
    assert os.path.isfile(VIDEO)
    os.replace(VIDEO, backup)
    try:
        cases = [
            (96 + 2 * secrets.randbelow(12), 64 + 2 * secrets.randbelow(10), 73 + secrets.randbelow(31)),
            (128 + 2 * secrets.randbelow(12), 72 + 2 * secrets.randbelow(10), 89 + secrets.randbelow(37)),
        ]
        answers = []
        for width, height, frames in cases:
            make_unpredictable_video(VIDEO, width, height, frames)
            expected = reference_count(VIDEO)
            _, actual = run_analyzer(FAST, timeout=30)
            assert actual == expected, (
                f"Incorrect result on generated video: expected {expected}, got {actual}"
            )
            answers.append(expected)
            os.unlink(VIDEO)
        assert len(answers) == 2
    finally:
        if os.path.exists(VIDEO):
            os.unlink(VIDEO)
        os.replace(backup, VIDEO)


def ssh_forward_processes():
    uid = pwd.getpwnam("user").pw_uid
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        proc = f"/proc/{name}"
        try:
            if os.stat(proc).st_uid != uid:
                continue
            raw = open(f"{proc}/cmdline", "rb").read()
            argv = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
        except (OSError, ProcessLookupError):
            continue
        if not argv or os.path.basename(argv[0]) != "ssh":
            continue
        forwards = []
        for i, arg in enumerate(argv):
            if arg == "-L" and i + 1 < len(argv):
                forwards.append(argv[i + 1])
            elif arg.startswith("-L") and len(arg) > 2:
                forwards.append(arg[2:])
        valid_forward = any(
            re.fullmatch(r"(?:[^:]+:)?9999:(?:localhost|127\.0\.0\.1):8080", value)
            for value in forwards
        )
        valid_host = any(
            arg in ("localhost", "127.0.0.1", "user@localhost", "user@127.0.0.1")
            for arg in argv[1:]
        )
        if valid_forward and valid_host:
            matches.append((int(name), argv))
    return matches


def remove_existing_forwarders():
    for pid, _ in ssh_forward_processes():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while ssh_forward_processes() and time.time() < deadline:
        time.sleep(0.1)
    for pid, _ in ssh_forward_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_deploy():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", DEPLOY],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"deploy.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    )


def user_crontab():
    result = subprocess.run(
        ["crontab", "-u", "user", "-l"], capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to read user crontab after deployment."
    return result.stdout


def matching_cron_lines(text):
    matches = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        every_minute = re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+", stripped)
        analyzer = "/home/user/fast_analyzer.py" in stripped
        netcat = re.search(
            r"\|\s*nc(?:\s+-\S+)*\s+(?:localhost|127\.0\.0\.1)\s+9999(?:\s|$)",
            stripped,
        )
        if every_minute and analyzer and netcat:
            matches.append(stripped)
    return matches


def verify_forwarding_path():
    ready = threading.Event()
    errors = []
    nonce = secrets.token_bytes(32)
    reply = b"verified:" + nonce

    def endpoint():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", 8080))
            server.listen(1)
            server.settimeout(10)
            ready.set()
            conn, _ = server.accept()
            with conn:
                conn.settimeout(5)
                received = b""
                while len(received) < len(nonce):
                    chunk = conn.recv(len(nonce) - len(received))
                    if not chunk:
                        break
                    received += chunk
                if received != nonce:
                    errors.append(f"endpoint received {received!r}, expected nonce")
                conn.sendall(reply)
        except Exception as exc:
            errors.append(repr(exc))
            ready.set()
        finally:
            server.close()

    thread = threading.Thread(target=endpoint, daemon=True)
    thread.start()
    assert ready.wait(3), "Metrics endpoint did not start."
    assert not errors, f"Could not establish controlled endpoint on port 8080: {errors}"

    deadline = time.time() + 10
    last_error = None
    received = b""
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 9999), timeout=2) as client:
                client.settimeout(3)
                client.sendall(nonce)
                while len(received) < len(reply):
                    chunk = client.recv(len(reply) - len(received))
                    if not chunk:
                        break
                    received += chunk
                break
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
    thread.join(timeout=5)
    assert not errors, f"Forwarding endpoint error: {errors}"
    assert received == reply, (
        f"Port 9999 did not forward traffic to localhost:8080: {last_error}"
    )


def test_deploy_script_tunnel_and_cron_are_functional_and_idempotent():
    assert os.path.isfile(DEPLOY), f"{DEPLOY} does not exist."
    assert os.access(DEPLOY, os.X_OK), f"{DEPLOY} is not executable."

    remove_existing_forwarders()
    subprocess.run(["crontab", "-u", "user", "-r"], capture_output=True)

    run_deploy()
    first_processes = ssh_forward_processes()
    assert len(first_processes) == 1, (
        f"Expected exactly one user SSH -L 9999:localhost:8080 tunnel, found {first_processes}"
    )
    first_pids = {pid for pid, _ in first_processes}
    first_cron = matching_cron_lines(user_crontab())
    assert len(first_cron) == 1, (
        f"Expected exactly one every-minute analyzer-to-netcat cron entry, found {first_cron}"
    )

    run_deploy()
    second_processes = ssh_forward_processes()
    second_pids = {pid for pid, _ in second_processes}
    assert len(second_processes) == 1, "Running deploy.sh twice spawned duplicate tunnels."
    assert second_pids == first_pids, "Running deploy.sh twice replaced or duplicated the live tunnel."
    second_cron = matching_cron_lines(user_crontab())
    assert len(second_cron) == 1, "Running deploy.sh twice duplicated the cron entry."

    verify_forwarding_path()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
