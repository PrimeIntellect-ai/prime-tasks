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
import secrets
import shutil
import subprocess
import tempfile
import time

import pytest
import requests

SRC = "/home/user/src"
ANALYZER = f"{SRC}/analyzer"
LIBCORE = f"{SRC}/lib/libcore.so"
FRAMES = "/home/user/frames"
VIDEO = "/app/test_stream.mp4"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, **kwargs)


def analyzer_output(frame):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{SRC}/lib" + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )
    return run([ANALYZER, frame], env=env).stdout


def test_01_analyzer_built_by_build_script():
    assert os.path.isfile(f"{SRC}/build.sh"), "build.sh does not exist"

    # Ensure the submitted build script really creates the artifact rather than
    # accepting a pre-created dummy file.
    if os.path.lexists(ANALYZER):
        os.unlink(ANALYZER)
    result = subprocess.run(["bash", "build.sh"], cwd=SRC,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=30)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert os.path.exists(ANALYZER), f"The compiled binary {ANALYZER} does not exist."
    assert os.path.isfile(ANALYZER), f"{ANALYZER} is not a regular file."
    assert os.access(ANALYZER, os.X_OK), f"The file {ANALYZER} is not executable."
    with open(ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer is not a compiled ELF executable"

    dynamic = run(["readelf", "-d", ANALYZER]).stdout.decode(errors="replace")
    assert "Shared library: [libcore.so]" in dynamic, \
        "analyzer is not dynamically linked against libcore.so"

    assert analyzer_output(f"{FRAMES}/frame_14.png") == b"RESULT_SCORE_84\n"
    assert analyzer_output(f"{FRAMES}/frame_05.png") == b"RESULT_SCORE_10\n"


def test_02_analyzer_actually_calls_libcore():
    # Substitute a verifier-generated ABI-compatible library. The unpredictable
    # output proves that analyzer actually dispatches to libcore at runtime.
    token = "LIB_PROBE_" + secrets.token_hex(16)
    backup = LIBCORE + ".verifier-backup"
    source = LIBCORE + ".verifier-probe.c"
    assert os.path.isfile(LIBCORE)
    if os.path.lexists(backup):
        os.unlink(backup)
    os.replace(LIBCORE, backup)
    try:
        with open(source, "w") as f:
            f.write('#include <stdio.h>\n'
                    'void process_image(const char *p) { (void)p; '
                    f'printf("{token}\\n"); }}\n')
        run(["gcc", "-shared", "-fPIC", "-o", LIBCORE, source])
        got = analyzer_output(f"{FRAMES}/frame_23.png")
        assert got == (token + "\n").encode(), \
            "analyzer did not use the linked libcore.so implementation"
    finally:
        if os.path.lexists(LIBCORE):
            os.unlink(LIBCORE)
        os.replace(backup, LIBCORE)
        if os.path.exists(source):
            os.unlink(source)


def decode_rgb(path):
    return run(["ffmpeg", "-v", "error", "-i", path,
                "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]).stdout


def test_03_frames_extracted_from_video():
    with tempfile.TemporaryDirectory(prefix="expected-frames-") as expected:
        run(["ffmpeg", "-v", "error", "-i", VIDEO, "-frames:v", "30",
             os.path.join(expected, "frame_%02d.png")])

        for i in range(1, 31):
            frame_path = f"{FRAMES}/frame_{i:02d}.png"
            expected_path = os.path.join(expected, f"frame_{i:02d}.png")
            assert os.path.exists(frame_path), \
                f"Frame {frame_path} does not exist. Did you extract all 30 frames correctly?"
            assert os.path.isfile(frame_path), f"Path {frame_path} is not a file."
            assert os.path.getsize(frame_path) > 0, f"Frame {frame_path} is empty."
            with open(frame_path, "rb") as f:
                assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{frame_path} is not a PNG"
            assert decode_rgb(frame_path) == decode_rgb(expected_path), \
                f"{frame_path} is not frame {i} from {VIDEO}"


def server_is_bound_to_loopback():
    # /proc/net/tcp encodes IPv4 addresses in little-endian hex. Port 8080 is 1F90.
    try:
        with open("/proc/net/tcp") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                if fields[1] == "0100007F:1F90" and fields[3] == "0A":
                    return True
    except OSError:
        pass
    return False


session = requests.Session()
session.trust_env = False


def get_frame(number):
    url = f"http://127.0.0.1:8080/analyze?frame={number:02d}"
    try:
        return session.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to {url} failed. Is the server running? Error: {e}")


def assert_valid_exact_response(response, expected):
    assert response.status_code == 200, \
        f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    assert response.content == expected, \
        f"Response body was not the exact analyzer stdout: {response.content!r} != {expected!r}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
    assert "Content-Length" in response.headers
    assert int(response.headers["Content-Length"]) == len(expected)


def test_04_http_server_frame_14():
    assert os.path.isfile("/home/user/server.sh"), "server.sh does not exist"
    assert server_is_bound_to_loopback(), "No server is listening on 127.0.0.1:8080"
    response = get_frame(14)
    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    assert "RESULT_SCORE_84" in response.text, f"Expected 'RESULT_SCORE_84' in response body for frame 14, got: {response.text}"
    assert_valid_exact_response(response, analyzer_output(f"{FRAMES}/frame_14.png"))


def test_05_http_server_frame_05():
    response = get_frame(5)
    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    assert "RESULT_SCORE_10" in response.text, f"Expected 'RESULT_SCORE_10' in response body for frame 05, got: {response.text}"
    assert_valid_exact_response(response, analyzer_output(f"{FRAMES}/frame_05.png"))


def test_06_server_invokes_analyzer_with_requested_frame():
    # Replace analyzer temporarily with an unpredictable probe. This prevents a
    # server hardcoded for the two public examples from passing.
    token = "HTTP_PROBE_" + secrets.token_hex(16)
    requested = secrets.choice([i for i in range(1, 31) if i not in (5, 14)])
    expected_arg = f"{FRAMES}/frame_{requested:02d}.png"
    log_path = f"/tmp/analyzer-probe-{secrets.token_hex(8)}.log"
    backup = ANALYZER + ".verifier-backup"

    if os.path.lexists(backup):
        os.unlink(backup)
    os.replace(ANALYZER, backup)
    try:
        with open(ANALYZER, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s\\n' \"$@\" >> {log_path}\n")
            f.write(f"printf '%s\\n' '{token}'\n")
        os.chmod(ANALYZER, 0o755)

        response = get_frame(requested)
        assert_valid_exact_response(response, (token + "\n").encode())

        deadline = time.time() + 2
        while not os.path.exists(log_path) and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.exists(log_path), "The HTTP server did not invoke analyzer"
        with open(log_path) as f:
            args = f.read().splitlines()
        assert args == [expected_arg], \
            f"Server invoked analyzer with {args!r}, expected {[expected_arg]!r}"
    finally:
        if os.path.lexists(ANALYZER):
            os.unlink(ANALYZER)
        os.replace(backup, ANALYZER)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
