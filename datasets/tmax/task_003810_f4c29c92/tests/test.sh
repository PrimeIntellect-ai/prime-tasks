#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import signal
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests
from scipy.optimize import curve_fit

URL = "http://127.0.0.1:8000/stats"
TOKEN = {"Authorization": "Bearer diff_token_99"}
PID_FILE = "/home/user/server.pid"
PDB_FILE = "/app/tracer.pdb"
VIDEO_FILE = "/app/diffusion.mp4"


def read_pid():
    assert os.path.isfile(PID_FILE), f"Missing PID file: {PID_FILE}"
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    return int(pid_str)


def pid_is_alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split()[2] != "Z"
    except (OSError, FileNotFoundError, ProcessLookupError):
        return False


def listening_socket_inodes():
    inodes = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    port = int(local_address.rsplit(":", 1)[1], 16)
                    if port == 8000 and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pid_owns_listener(pid):
    wanted = {f"socket:[{inode}]" for inode in listening_socket_inodes()}
    if not wanted:
        return False
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}") in wanted:
                    return True
            except OSError:
                pass
    except FileNotFoundError:
        return False
    return False


def request_stats(headers=TOKEN):
    try:
        return requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")


def capture_launch(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmd = [part.decode() for part in f.read().split(b"\0") if part]
    assert cmd, "Could not determine the server command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    with open(f"/proc/{pid}/environ", "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return cmd, cwd, env


def stop_pid(pid):
    if not pid_is_alive(pid):
        return
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and pid_is_alive(pid):
        time.sleep(0.05)
    if pid_is_alive(pid):
        os.kill(pid, signal.SIGKILL)
        deadline = time.time() + 2
        while time.time() < deadline and pid_is_alive(pid):
            time.sleep(0.05)


def start_server(launch):
    cmd, cwd, env = launch
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Server command exited early with status {proc.returncode}")
        try:
            response = requests.get(URL, timeout=0.5)
            if response.status_code in (200, 401):
                return proc
        except requests.exceptions.RequestException as e:
            last_error = e
        time.sleep(0.1)
    stop_pid(proc.pid)
    pytest.fail(f"Restarted server did not listen on 127.0.0.1:8000: {last_error}")


def write_challenge_inputs(n_ca, diffusion, intercept):
    with open(PDB_FILE, "w") as f:
        serial = 1
        for residue in range(1, n_ca + 1):
            f.write(f"ATOM  {serial:5d}  CA  ALA A {residue:4d}    10.000  10.000  10.000  1.00  0.00           C\n")
            serial += 1
            if residue % 7 == 0:
                f.write(f"ATOM  {serial:5d}  CB  ALA A {residue:4d}    11.000  10.000  10.000  1.00  0.00           C\n")
                serial += 1
        f.write("HETATM99999  CA  HOH B   1      20.000  20.000  20.000  1.00  0.00           O\n")

    width, height, fps, duration = 500, 100, 30, 10
    writer = cv2.VideoWriter(
        VIDEO_FILE, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height), False
    )
    assert writer.isOpened(), "Could not create challenge video"
    x = np.arange(width, dtype=float)
    for frame_number in range(fps * duration):
        t = frame_number / fps
        variance = 2.0 * diffusion * t + intercept
        profile = 245.0 * np.exp(-0.5 * ((x - 247.0) ** 2) / variance)
        frame = np.tile(np.clip(profile, 0, 255).astype(np.uint8), (height, 1))
        writer.write(frame)
    writer.release()


def derive_expected_from_inputs():
    n_ca = 0
    with open(PDB_FILE) as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                n_ca += 1

    cap = cv2.VideoCapture(VIDEO_FILE)
    assert cap.isOpened(), "Could not read challenge video"
    variances = []
    times = np.arange(10, dtype=float)

    def gaussian(x, amplitude, center, variance, offset):
        return offset + amplitude * np.exp(-0.5 * ((x - center) ** 2) / variance)

    for second in range(10):
        cap.set(cv2.CAP_PROP_POS_FRAMES, second * 30)
        ok, frame = cap.read()
        assert ok, f"Could not extract frame {second * 30}"
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        profile = gray.astype(float).sum(axis=0)
        x = np.arange(profile.size, dtype=float)
        baseline = float(profile.min())
        weights = np.maximum(profile - baseline, 0)
        center0 = float(np.sum(x * weights) / np.sum(weights))
        variance0 = float(np.sum(weights * (x - center0) ** 2) / np.sum(weights))
        params, _ = curve_fit(
            gaussian,
            x,
            profile,
            p0=(float(profile.max() - baseline), center0, variance0, baseline),
            bounds=([0, 0, 0.01, -np.inf], [np.inf, profile.size, np.inf, np.inf]),
            maxfev=20000,
        )
        variances.append(float(params[2]))
    cap.release()
    slope, _ = np.polyfit(times, np.asarray(variances), 1)
    return n_ca, n_ca / 100.0, round(float(slope / 2.0), 2)


def test_server_pid_exists():
    """Verify that the PID is valid, alive, and owns the required listener."""
    pid = read_pid()
    assert pid_is_alive(pid), f"PID {pid} is not a running process"
    assert pid_owns_listener(pid), f"PID {pid} does not own the listening socket on port 8000"


def test_unauthenticated_request():
    response = request_stats(headers={})
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


@pytest.mark.parametrize("bad_value", ["Bearer wrong_token", "diff_token_99", "Bearer diff_token_99 ", ""])
def test_incorrect_authorization_values(bad_value):
    response = request_stats(headers={"Authorization": bad_value})
    assert response.status_code == 401, f"Expected 401 for Authorization={bad_value!r}, got {response.status_code}"


def test_authenticated_request_and_response():
    response = request_stats()
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "N" in data, "Missing 'N' in JSON response"
    assert "k" in data, "Missing 'k' in JSON response"
    assert "D_app" in data, "Missing 'D_app' in JSON response"
    assert data["N"] == 240, f"Expected N=240, got {data['N']}"
    assert abs(data["k"] - 2.4) < 1e-5, f"Expected k=2.4, got {data['k']}"
    d_app = data["D_app"]
    assert isinstance(d_app, (int, float)), f"D_app must be a number, got {type(d_app)}"
    assert 40.0 <= d_app <= 50.0, f"Expected D_app to be between 40.0 and 50.0, got {d_app}"


def test_recomputes_results_from_pdb_and_video():
    original_pid = read_pid()
    launch = capture_launch(original_pid)
    pdb_backup = "/tmp/tracer.pdb.verifier-backup"
    video_backup = "/tmp/diffusion.mp4.verifier-backup"
    shutil.copy2(PDB_FILE, pdb_backup)
    shutil.copy2(VIDEO_FILE, video_backup)

    n_ca = 130 + secrets.randbelow(190)
    if n_ca == 240:
        n_ca += 1
    diffusion = 57.0 + secrets.randbelow(17) + secrets.randbelow(100) / 100.0
    intercept = 14.0 + secrets.randbelow(12)
    challenge_proc = None

    try:
        stop_pid(original_pid)
        write_challenge_inputs(n_ca, diffusion, intercept)
        expected_n, expected_k, expected_d = derive_expected_from_inputs()
        assert expected_n == n_ca
        challenge_proc = start_server(launch)

        response = request_stats()
        assert response.status_code == 200, f"Expected 200 after input change, got {response.status_code}: {response.text}"
        data = response.json()
        assert data.get("N") == expected_n, f"Expected recomputed N={expected_n}, got {data.get('N')}"
        assert isinstance(data.get("k"), (int, float)), f"k must be numeric, got {data.get('k')!r}"
        assert abs(data["k"] - expected_k) < 1e-5, f"Expected recomputed k={expected_k}, got {data['k']}"
        assert isinstance(data.get("D_app"), (int, float)), f"D_app must be numeric, got {data.get('D_app')!r}"
        assert abs(float(data["D_app"]) - expected_d) <= 0.20, (
            f"Expected D_app={expected_d} derived from challenge video, got {data['D_app']}"
        )
    finally:
        if challenge_proc is not None:
            stop_pid(challenge_proc.pid)
        elif os.path.exists(PID_FILE):
            try:
                candidate = int(open(PID_FILE).read().strip())
                if candidate != original_pid:
                    stop_pid(candidate)
            except (ValueError, OSError):
                pass
        shutil.copy2(pdb_backup, PDB_FILE)
        shutil.copy2(video_backup, VIDEO_FILE)
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass
        restored = start_server(launch)
        deadline = time.time() + 5
        while time.time() < deadline:
            if os.path.isfile(PID_FILE):
                break
            time.sleep(0.05)
        assert os.path.isfile(PID_FILE), "Restored server did not recreate its PID file"
        restored_pid = read_pid()
        assert pid_is_alive(restored_pid), "Restored server PID is not alive"
        assert pid_owns_listener(restored_pid), "Restored server PID does not own port 8000"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
