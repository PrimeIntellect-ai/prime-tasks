#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import pwd
import re
import signal
import subprocess
import tempfile
import threading
import time

import cv2
import numpy as np
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _user_preexec():
    user = pwd.getpwnam("user")
    os.setsid()
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def _read_frames(path):
    with open(path, "r") as f:
        return {int(line.strip()) for line in f if line.strip().isdigit()}


def _f1(preds, truth):
    tp = len(preds & truth)
    fp = len(preds - truth)
    fn = len(truth - preds)
    if tp == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * precision * recall / (precision + recall)


def _script_candidates():
    excluded = {"router_fstab", "down_frames.txt", "lb.conf", "nginx.pid", "error.log"}
    candidates = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            if name in excluded:
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as f:
                    first = f.readline(256).decode("utf-8", "ignore").lower()
            except OSError:
                continue
            if name.endswith((".sh", ".bash", ".py")) or first.startswith("#!"):
                candidates.append(path)
    return candidates


def _run_script(path):
    try:
        with open(path, "rb") as f:
            first = f.readline(256).decode("utf-8", "ignore").lower()
    except OSError:
        first = ""
    if path.endswith(".py") or "python" in first:
        cmd = ["python3", path]
    else:
        cmd = ["bash", path]

    output_path = "/home/user/down_frames.txt"
    try:
        os.unlink(output_path)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        cmd,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
        preexec_fn=_user_preexec,
    )
    if result.returncode != 0:
        raise AssertionError(f"{path} failed: {result.stderr[-1000:]}")
    if not os.path.isfile(output_path):
        with open(output_path, "w") as f:
            f.write(result.stdout)
        user = pwd.getpwnam("user")
        os.chown(output_path, user.pw_uid, user.pw_gid)
    return _read_frames(output_path)


def _derive_red_frames(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not decode {video_path}"
    result = set()
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        roi = frame[0:50, 0:50]
        mean_b, mean_g, mean_r = roi.mean(axis=(0, 1))
        if mean_r > mean_g and mean_r > mean_b:
            result.add(index)
        index += 1
    cap.release()
    return result


def test_router_fstab():
    fstab_path = "/home/user/router_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} is missing."

    with open(fstab_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith('#')]

    assert len(lines) == 1, f"Expected exactly one valid fstab entry, found {len(lines)}."

    fields = lines[0].split()
    assert len(fields) >= 4, "fstab entry must have at least 4 fields (fs_spec, fs_file, fs_vfstype, fs_mntops)."

    fs_spec, fs_file, fs_vfstype, fs_mntops = fields[:4]

    assert fs_spec == "/app/router_fs.ext4", f"Expected fs_spec to be /app/router_fs.ext4, got {fs_spec}"
    assert fs_file == "/mnt/router", f"Expected fs_file to be /mnt/router, got {fs_file}"

    mntops = fs_mntops.split(',')
    assert 'loop' in mntops, "fstab mount options must include 'loop'"
    assert 'ro' in mntops, "fstab mount options must include 'ro'"
    assert 'user' in mntops or 'users' in mntops, "fstab mount options must include 'user' or 'users'"


def test_processing_script_exists_and_processes_video():
    candidates = _script_candidates()
    assert candidates, "No video-processing script was found under /home/user."

    original = "/app/vnc_capture.mp4"
    backup = tempfile.mktemp(prefix="vnc_capture_backup_", suffix=".mp4", dir="/app")
    os.replace(original, backup)
    selected = None
    errors = []
    try:
        writer = cv2.VideoWriter(original, cv2.VideoWriter_fourcc(*"mp4v"), 30, (640, 480))
        assert writer.isOpened(), "Could not create verifier probe video"
        rng = np.random.default_rng()
        probe_truth = set(rng.choice(np.arange(7, 83), size=23, replace=False).tolist())
        for i in range(90):
            frame = np.zeros((480, 640, 3), dtype=np.uint8)
            frame[0:50, 0:50] = (0, 0, 255) if i in probe_truth else (0, 255, 0)
            writer.write(frame)
        writer.release()
        os.chmod(original, 0o644)

        decoded_truth = _derive_red_frames(original)
        for candidate in candidates:
            try:
                preds = _run_script(candidate)
                score = _f1(preds, decoded_truth)
                if score >= 0.95:
                    selected = candidate
                    break
                errors.append(f"{candidate}: probe F1={score:.4f}")
            except Exception as exc:
                errors.append(f"{candidate}: {exc}")
    finally:
        try:
            os.unlink(original)
        except FileNotFoundError:
            pass
        os.replace(backup, original)

    assert selected is not None, "No processing script correctly handled the probe video. " + " | ".join(errors)
    _run_script(selected)


def test_down_frames_f1_score():
    pred_file = "/home/user/down_frames.txt"
    assert os.path.isfile(pred_file), f"File {pred_file} is missing."

    try:
        preds = _read_frames(pred_file)
    except Exception as e:
        assert False, f"Error reading {pred_file}: {e}"

    ground_truth = list(range(45, 86)) + list(range(160, 211)) + list(range(260, 281))
    true_set = set(ground_truth)
    f1 = _f1(preds, true_set)
    assert f1 >= 0.95, f"F1 Score is {f1:.4f}, which is below the threshold of 0.95."


class _BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = str(self.server.server_port).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def test_nginx_config():
    conf_path = "/home/user/lb.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."

    with open(conf_path, 'r') as f:
        content = f.read()

    assert re.search(r'daemon\s+off\s*;', content), "Nginx config missing 'daemon off;'"
    assert re.search(r'pid\s+/home/user/nginx\.pid\s*;', content), "Nginx config missing 'pid /home/user/nginx.pid;'"
    assert re.search(r'error_log\s+/home/user/error\.log\s*;', content), "Nginx config missing 'error_log /home/user/error.log;'"
    assert re.search(r'listen\s+127\.0\.0\.1:8080\s*;', content), "Nginx config missing 'listen 127.0.0.1:8080;'"
    assert re.search(r'server\s+127\.0\.0\.1:9001\s*;', content), "Nginx config missing backend server 127.0.0.1:9001"
    assert re.search(r'server\s+127\.0\.0\.1:9002\s*;', content), "Nginx config missing backend server 127.0.0.1:9002"
    assert re.search(r'server\s+127\.0\.0\.1:9003\s*;', content), "Nginx config missing backend server 127.0.0.1:9003"
    assert re.search(r'proxy_pass\s+http://', content), "Nginx config missing proxy_pass directive to load balance"

    syntax = subprocess.run(
        ["nginx", "-t", "-c", conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        preexec_fn=_user_preexec,
    )
    assert syntax.returncode == 0, f"nginx -t failed:\n{syntax.stdout}\n{syntax.stderr}"

    servers = []
    threads = []
    nginx = None
    try:
        for port in (9001, 9002, 9003):
            server = ThreadingHTTPServer(("127.0.0.1", port), _BackendHandler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            servers.append(server)
            threads.append(thread)

        nginx = subprocess.Popen(
            ["nginx", "-c", conf_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=_user_preexec,
        )

        seen = set()
        last_error = None
        deadline = time.time() + 10
        while time.time() < deadline and len(seen) < 3:
            if nginx.poll() is not None:
                out, err = nginx.communicate()
                raise AssertionError(f"Nginx exited before serving requests:\n{out}\n{err}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
                conn.request("GET", "/")
                response = conn.getresponse()
                body = response.read().decode().strip()
                conn.close()
                assert response.status == 200, f"Proxy returned HTTP {response.status}"
                if body in {"9001", "9002", "9003"}:
                    seen.add(int(body))
                last_error = None
            except (OSError, http.client.HTTPException) as exc:
                last_error = exc
                time.sleep(0.15)

        assert seen == {9001, 9002, 9003}, f"Proxy did not round-robin across all backends; saw {sorted(seen)}. Last error: {last_error}"
    finally:
        if nginx is not None and nginx.poll() is None:
            try:
                os.killpg(nginx.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                nginx.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(nginx.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for server in servers:
            server.shutdown()
            server.server_close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
