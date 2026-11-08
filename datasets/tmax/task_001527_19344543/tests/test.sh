#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time

import pytest
import requests


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def supervisor_pids():
    found = set()
    for name in os.listdir("/proc"):
        if name.isdigit() and "/home/user/supervisor.sh" in proc_cmdline(int(name)):
            found.add(int(name))
    return found


def has_ancestor(pid, ancestors):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().split()[3])
        except (OSError, ValueError, IndexError):
            return False
    return pid in ancestors


def status_check():
    with socket.create_connection(("127.0.0.1", 9001), timeout=5) as sock:
        sock.sendall(b"STATUS\n")
        return sock.recv(1024)


def video_colors(path):
    result = run([
        "ffmpeg", "-v", "error", "-i", path, "-vf", "fps=1,scale=1:1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])
    raw = result.stdout
    assert raw and len(raw) % 3 == 0, f"Could not independently decode frames from {path}"
    return [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]


def primary_color(rgb):
    return max(range(3), key=lambda i: rgb[i])


def red_count(colors):
    return sum(1 for rgb in colors if primary_color(rgb) == 0 and rgb[0] >= 180)


def archive_colors(path):
    assert os.path.exists(path), f"Backup archive not found at {path} after processing"
    assert os.path.isfile(path), f"Backup path {path} is not a file"
    assert os.path.getsize(path) > 0, f"Backup archive at {path} is empty"

    try:
        archive = tarfile.open(path, mode="r:gz")
    except (tarfile.TarError, OSError) as exc:
        pytest.fail(f"Backup is not a valid gzip-compressed tar archive: {exc}")

    with archive, tempfile.TemporaryDirectory() as td:
        members = [m for m in archive.getmembers() if m.isfile()]
        assert members, "Backup archive contains no frame files"
        assert all(not m.issym() and not m.islnk() for m in archive.getmembers()), \
            "Backup archive must not contain links"

        def natural_key(member):
            return [int(x) if x.isdigit() else x.lower()
                    for x in re.split(r"(\d+)", member.name)]

        colors = []
        for index, member in enumerate(sorted(members, key=natural_key)):
            assert member.size > 0, f"Archived frame {member.name} is empty"
            src = archive.extractfile(member)
            assert src is not None
            frame_path = os.path.join(td, f"frame-{index}")
            with open(frame_path, "wb") as dst:
                shutil.copyfileobj(src, dst)
            try:
                decoded = run([
                    "ffmpeg", "-v", "error", "-i", frame_path,
                    "-vf", "scale=1:1", "-frames:v", "1",
                    "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
                ]).stdout
            except subprocess.CalledProcessError as exc:
                pytest.fail(f"Archived member {member.name} is not a decodable image: "
                            f"{exc.stderr.decode(errors='replace')}")
            assert len(decoded) == 3, f"Archived member {member.name} is not one image frame"
            colors.append(tuple(decoded))
        return colors


def assert_archive_matches(video_path):
    expected = video_colors(video_path)
    archived = archive_colors("/home/user/backup/frames.tar.gz")
    assert len(archived) == len(expected), \
        f"Archive has {len(archived)} frames; ffmpeg at 1 fps extracts {len(expected)}"
    assert [primary_color(c) for c in archived] == [primary_color(c) for c in expected], \
        "Archived frames do not correspond to the source video's 1-fps frame sequence"


def request_process(expected_count):
    url = "http://127.0.0.1:8080/process"
    try:
        response = requests.get(url, timeout=45)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to Nginx at {url}. Is Nginx running and configured correctly?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out.")

    assert response.status_code == 200, \
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip() == "application/json"
    assert "nginx" in response.headers.get("Server", "").lower(), \
        "Port 8080 response was not served through Nginx"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "red_frames" in data, "Response JSON missing 'red_frames' key"
    assert data["red_frames"] == expected_count, \
        f"Expected {expected_count} red frames, got {data['red_frames']}"
    assert set(data) == {"red_frames"}, "Response contains unexpected JSON fields"
    return response


def test_supervisor_script_and_build():
    script_path = "/home/user/supervisor.sh"
    assert os.path.exists(script_path), f"Supervisor script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Supervisor script at {script_path} is not executable"
    assert supervisor_pids(), "The supervisor script is not running"

    source = "/home/user/src/backend.cpp"
    assert os.path.isfile(source), f"Backend source not found at {source}"
    result = subprocess.run([
        "g++", "-std=c++17", "-pthread", source, "-o", "/tmp/verifier_backend_build"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, \
        f"The repaired C++ backend does not compile:\n{result.stderr.decode(errors='replace')}"


def test_nginx_configuration_and_process():
    conf = "/home/user/nginx/nginx.conf"
    result = subprocess.run(["nginx", "-t", "-c", conf], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    assert result.returncode == 0, \
        f"Nginx configuration is invalid: {result.stderr.decode(errors='replace')}"
    text = open(conf).read()
    text = re.sub(r"#.*", "", text)
    assert re.search(r"listen\s+127\.0\.0\.1:8080\s*;", text), \
        "Nginx is not configured to listen on 127.0.0.1:8080"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000\s*;", text), \
        "Nginx does not proxy to the backend on 127.0.0.1:9000"

    pids = listener_pids(8080)
    assert pids, "Nothing is listening on port 8080"
    nginx_pids = {p for p in pids if os.path.basename(proc_exe(p)) == "nginx"}
    assert nginx_pids, "Port 8080 is not owned by an Nginx process"
    assert any(conf in proc_cmdline(p) for p in nginx_pids), \
        "The Nginx listener was not started with /home/user/nginx/nginx.conf"


def test_raw_tcp_status_and_shared_backend():
    try:
        response = status_check()
    except ConnectionRefusedError:
        pytest.fail("Connection refused to 127.0.0.1:9001. Is the raw TCP server running?")
    except socket.timeout:
        pytest.fail("Connection to 127.0.0.1:9001 timed out.")
    assert response == b"OK\n", f"Expected 'OK\\n' from raw TCP status, got {response!r}"

    http_pids = listener_pids(9000)
    status_pids = listener_pids(9001)
    shared = http_pids & status_pids
    assert shared, "Ports 9000 and 9001 are not served by the same backend process"
    assert any(open(proc_exe(pid), "rb").read(4) == b"\x7fELF" for pid in shared), \
        "The running backend is not a compiled native executable"


def test_supervisor_restarts_backend():
    supervisors = supervisor_pids()
    assert supervisors, "The supervisor script is not running"
    old = listener_pids(9000) & listener_pids(9001)
    assert old, "Backend is not listening on both required ports"
    for pid in old:
        os.kill(pid, 9)

    deadline = time.time() + 12
    new = set()
    while time.time() < deadline:
        new = (listener_pids(9000) & listener_pids(9001)) - old
        if new:
            try:
                if status_check() == b"OK\n":
                    break
            except OSError:
                pass
        time.sleep(0.2)
    else:
        pytest.fail("Supervisor did not restart the backend after it was killed")

    assert any(has_ancestor(pid, supervisors) for pid in new), \
        "Restarted backend is not a child of the running supervisor script"


def test_http_process_and_backup():
    source_video = "/app/surveillance.mp4"
    expected_colors = video_colors(source_video)
    expected = red_count(expected_colors)
    assert expected == 3, f"Provided video should contain 3 red frames, independently found {expected}"
    request_process(3)
    assert_archive_matches(source_video)


def test_process_uses_current_video_and_rebuilds_archive():
    source_video = "/app/surveillance.mp4"
    saved = "/tmp/original-surveillance.mp4"
    shutil.copy2(source_video, saved)
    dynamic = "/tmp/dynamic-surveillance.mp4"
    colors = ["blue", "red", "green", "blue", "red", "green"]
    cmd = ["ffmpeg", "-v", "error"]
    for color in colors:
        cmd += ["-f", "lavfi", "-i", f"color=c={color}:s=160x120:r=25:d=1"]
    cmd += ["-filter_complex", "".join(f"[{i}:v]" for i in range(len(colors))) +
            f"concat=n={len(colors)}:v=1:a=0[out]",
            "-map", "[out]", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", dynamic]
    run(cmd)
    shutil.copy2(dynamic, source_video)
    try:
        expected = red_count(video_colors(source_video))
        assert expected == 2, f"Verifier-generated video unexpectedly has {expected} red frames"
        request_process(expected)
        assert_archive_matches(source_video)
    finally:
        shutil.copy2(saved, source_video)

    # Return the service and archive to the required final state for the provided video.
    request_process(3)
    assert_archive_matches(source_video)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
