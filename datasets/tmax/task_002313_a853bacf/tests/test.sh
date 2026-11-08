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
import os
import re
import subprocess
import requests
import json
import time
import signal
from decimal import Decimal

VIDEO_PATH = "/app/data/surveillance.mp4"
SOURCE_PATH = "/home/user/analytics/src/backend.c"
HEADER_PATH = "/home/user/analytics/src/timestamps.h"
BACKEND_PATH = "/home/user/analytics/backend"
REBUILT_PATH = "/tmp/backend_verified"


def get_all_expected_timestamps():
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=pts_time",
        "-of", "default=noprint_wrappers=1:nokey=1",
        VIDEO_PATH,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"ffprobe failed: {result.stderr}"
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines, "ffprobe returned no frame timestamps"
    return [Decimal(line) for line in lines]


EXPECTED_TIMESTAMPS = get_all_expected_timestamps()


def get_expected_timestamp(frame_index):
    if 0 <= frame_index < len(EXPECTED_TIMESTAMPS):
        return float(EXPECTED_TIMESTAMPS[frame_index])
    return None


def test_bashrc_env_var():
    """Check that PIPELINE_STRICT=1 is in ~/.bashrc"""
    bashrc_path = os.path.expanduser("~/.bashrc")
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert re.search(r"PIPELINE_STRICT=1", content), "PIPELINE_STRICT=1 not found in ~/.bashrc"


def test_timestamps_header():
    """Check that timestamps.h exists and has the correct format."""
    assert os.path.exists(HEADER_PATH), f"{HEADER_PATH} does not exist"
    with open(HEADER_PATH, "r") as f:
        content = f.read()
    assert "const double frame_timestamps[]" in content, "Array declaration not found in timestamps.h"
    assert "{" in content and "}" in content, "Array braces not found in timestamps.h"


def test_complete_timestamps_header():
    """Verify that the header contains every ffprobe timestamp in sequence."""
    with open(HEADER_PATH, "r") as f:
        content = f.read()
    match = re.search(
        r"const\s+double\s+frame_timestamps\s*\[\s*\]\s*=\s*\{(.*?)\}\s*;",
        content,
        re.DOTALL,
    )
    assert match, "timestamps.h does not contain the required array declaration"
    entries = [item.strip() for item in match.group(1).split(",")]
    if entries and entries[-1] == "":
        entries.pop()
    assert all(entries), "timestamps.h contains an empty timestamp entry"
    try:
        actual = [Decimal(item) for item in entries]
    except Exception as exc:
        assert False, f"timestamps.h contains a non-numeric timestamp: {exc}"
    assert len(actual) == len(EXPECTED_TIMESTAMPS), (
        f"Expected {len(EXPECTED_TIMESTAMPS)} timestamps, found {len(actual)}"
    )
    assert actual == EXPECTED_TIMESTAMPS, "timestamps.h does not contain all timestamps in ffprobe order"


def test_backend_files_exist():
    """Check that the C backend source and executable exist."""
    assert os.path.exists(SOURCE_PATH), "backend.c source not found"
    assert os.path.exists(BACKEND_PATH), "backend executable not found"
    assert os.access(BACKEND_PATH, os.X_OK), "backend is not executable"


def test_backend_is_compiled_and_includes_header():
    with open(SOURCE_PATH, "r") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]timestamps\.h[>\"]", source), (
        "backend.c does not include timestamps.h"
    )
    with open(BACKEND_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backend is not a compiled ELF executable"


def test_nginx_files_exist():
    """Check that Nginx config and certs exist."""
    assert os.path.exists("/home/user/analytics/nginx.conf"), "nginx.conf not found"
    assert os.path.exists("/home/user/analytics/certs/server.crt"), "TLS certificate not found"
    assert os.path.exists("/home/user/analytics/certs/server.key"), "TLS private key not found"


def test_processes_running():
    """Check that backend and nginx processes are running."""
    ps_cmd = subprocess.run(["ps", "-ef"], capture_output=True, text=True)
    assert "nginx" in ps_cmd.stdout, "nginx process is not running"
    assert "backend" in ps_cmd.stdout, "backend process is not running"


def test_http_backend_endpoint():
    """Verify the C backend responds correctly on HTTP port 9000."""
    expected_time = get_expected_timestamp(10)
    assert expected_time is not None, "Video does not have at least 11 frames"
    url = "http://127.0.0.1:9000/api/time?frame=10"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to backend at {url}: {e}"
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        assert False, f"Response is not valid JSON: {response.text}"
    assert "frame" in data and "time" in data, "JSON payload missing 'frame' or 'time' keys"
    assert data["frame"] == 10, f"Expected frame 10, got {data['frame']}"
    assert abs(float(data["time"]) - expected_time) < 0.001, f"Expected time {expected_time}, got {data['time']}"


def test_https_nginx_endpoint():
    """Verify Nginx proxies correctly on HTTPS port 8443."""
    expected_time = get_expected_timestamp(10)
    assert expected_time is not None, "Video does not have at least 11 frames"
    url = "https://127.0.0.1:8443/api/time?frame=10"
    try:
        response = requests.get(url, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to Nginx at {url}: {e}"
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        assert False, f"Response is not valid JSON: {response.text}"
    assert "frame" in data and "time" in data, "JSON payload missing 'frame' or 'time' keys"
    assert data["frame"] == 10, f"Expected frame 10, got {data['frame']}"
    assert abs(float(data["time"]) - expected_time) < 0.001, f"Expected time {expected_time}, got {data['time']}"


def test_https_nginx_404():
    """Verify out-of-bounds frame returns 404 on HTTPS port 8443."""
    url = "https://127.0.0.1:8443/api/time?frame=999999"
    try:
        response = requests.get(url, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to Nginx at {url}: {e}"
    assert response.status_code == 404, f"Expected status 404 for out-of-bounds frame, got {response.status_code}"


def kill_port_listeners(port):
    socket_inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted_port and fields[3] == "0A":
                socket_inodes.add(fields[9])
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            continue
    time.sleep(0.5)


def parse_exact_payload(response, frame, expected):
    assert response.status_code == 200, (
        f"Frame {frame}: expected HTTP 200, got {response.status_code}: {response.text}"
    )
    try:
        data = json.loads(response.text, parse_float=Decimal, parse_int=int)
    except (json.JSONDecodeError, ValueError) as exc:
        assert False, f"Frame {frame}: invalid JSON response: {exc}: {response.text}"
    assert isinstance(data, dict), f"Frame {frame}: response is not a JSON object"
    assert "frame" in data and "time" in data, f"Frame {frame}: missing frame or time"
    assert type(data["frame"]) is int and data["frame"] == frame, (
        f"Frame {frame}: incorrect frame value {data['frame']!r}"
    )
    assert isinstance(data["time"], (int, Decimal)) and not isinstance(data["time"], bool), (
        f"Frame {frame}: time must be a JSON number"
    )
    assert Decimal(data["time"]) == expected, (
        f"Frame {frame}: expected exact timestamp {expected}, got {data['time']}"
    )


def test_recompiled_backend_all_frames_and_exact_routes():
    """Compile submitted C source, run it, and exercise every derived frame index."""
    compile_result = subprocess.run(
        ["gcc", "-std=gnu11", "-O2", SOURCE_PATH, "-o", REBUILT_PATH, "-lm", "-pthread"],
        cwd="/home/user/analytics/src",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "backend.c failed to compile:\n" + compile_result.stdout + compile_result.stderr
    )
    assert os.access(REBUILT_PATH, os.X_OK), "Recompiled backend is not executable"

    kill_port_listeners(9000)
    proc = subprocess.Popen(
        [REBUILT_PATH],
        cwd="/home/user/analytics/src",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace") if proc.stderr else ""
                assert False, f"Recompiled backend exited before serving: {stderr}"
            try:
                requests.get("http://127.0.0.1:9000/api/time?frame=0", timeout=0.25)
                break
            except requests.exceptions.RequestException:
                time.sleep(0.05)
        else:
            assert False, "Recompiled backend did not listen on 127.0.0.1:9000"

        requests.packages.urllib3.disable_warnings()
        for frame, expected in enumerate(EXPECTED_TIMESTAMPS):
            direct = requests.get(
                f"http://127.0.0.1:9000/api/time?frame={frame}", timeout=3
            )
            parse_exact_payload(direct, frame, expected)

            proxied = requests.get(
                f"https://127.0.0.1:8443/api/time?frame={frame}",
                verify=False,
                timeout=3,
            )
            parse_exact_payload(proxied, frame, expected)

        for bad_index in (-1, len(EXPECTED_TIMESTAMPS), len(EXPECTED_TIMESTAMPS) + 1, 999999):
            for base, verify in (
                ("http://127.0.0.1:9000", True),
                ("https://127.0.0.1:8443", False),
            ):
                response = requests.get(
                    f"{base}/api/time?frame={bad_index}", verify=verify, timeout=3
                )
                assert response.status_code == 404, (
                    f"Out-of-bounds index {bad_index} returned {response.status_code} via {base}"
                )

        malformed = [
            "/api/time",
            "/api/time?frame=",
            "/api/time?frame=abc",
            "/api/time?frame=1.0",
            "/api/time?frame=0&extra=1",
            "/api/time?extra=1&frame=0",
            "/api/time?frame=0&frame=1",
            "/api/time/?frame=0",
            "/api/timeX?frame=0",
        ]
        for path in malformed:
            for base, verify in (
                ("http://127.0.0.1:9000", True),
                ("https://127.0.0.1:8443", False),
            ):
                response = requests.get(base + path, verify=verify, timeout=3)
                assert response.status_code != 200, (
                    f"Non-matching route unexpectedly succeeded: {base + path}"
                )

        for base, verify in (
            ("http://127.0.0.1:9000", True),
            ("https://127.0.0.1:8443", False),
        ):
            response = requests.post(base + "/api/time?frame=0", verify=verify, timeout=3)
            assert response.status_code != 200, f"POST unexpectedly succeeded via {base}"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
