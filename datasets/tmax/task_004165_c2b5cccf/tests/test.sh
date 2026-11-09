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
import hashlib
import json
import os
import re
import secrets
import subprocess
import uuid

import pytest
import requests

ANALYZER_DIR = "/home/user/analyzer"
ANALYZER = os.path.join(ANALYZER_DIR, "frame_analyzer")
SOURCE = os.path.join(ANALYZER_DIR, "frame_analyzer.c")
MAKEFILE = os.path.join(ANALYZER_DIR, "Makefile")
SERVER = "/home/user/api_server.sh"
VIDEO = "/app/drone_footage.mp4"
FRAME_SIZE = 854 * 480 * 3
AUTH = {"Authorization": "Bearer test-api-key-88"}


def extract_frame(time_sec):
    cmd = [
        "ffmpeg", "-y", "-ss", str(time_sec), "-i", VIDEO,
        "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Failed to extract frame with ffmpeg: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == FRAME_SIZE, f"Expected {FRAME_SIZE} raw bytes, got {len(result.stdout)}"
    return result.stdout


def run_analyzer(path, raw_bytes, suffix):
    raw_path = f"/tmp/verifier-frame-{suffix}-{uuid.uuid4().hex}.rgb"
    try:
        with open(raw_path, "wb") as f:
            f.write(raw_bytes)
        result = subprocess.run(
            [path, raw_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10,
            env={**os.environ, "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1"}
        )
        assert result.returncode == 0, result.stderr
        text = result.stdout.strip()
        assert re.fullmatch(r"[0-9]+", text), f"Analyzer returned non-numeric output: {text!r}"
        assert int(text) == sum(raw_bytes) % 256
    finally:
        try:
            os.unlink(raw_path)
        except FileNotFoundError:
            pass


def test_frame_analyzer_compiled_and_correct():
    assert os.path.isfile(SOURCE), f"Missing source: {SOURCE}"
    assert os.path.isfile(MAKEFILE), f"Missing Makefile: {MAKEFILE}"

    build = subprocess.run(
        ["make", "-B"], cwd=ANALYZER_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    output = build.stdout + build.stderr
    assert build.returncode == 0, f"Makefile build failed:\n{output}"
    assert not re.search(r"\bwarning:", output, re.IGNORECASE), f"Build emitted warnings:\n{output}"

    assert os.path.isfile(ANALYZER), f"Missing compiled executable: {ANALYZER}"
    assert os.access(ANALYZER, os.X_OK), f"File is not executable: {ANALYZER}"
    with open(ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "frame_analyzer is not a compiled ELF executable"

    strict_binary = f"/tmp/frame_analyzer-strict-{uuid.uuid4().hex}"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
         "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
         SOURCE, "-o", strict_binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Source does not compile cleanly:\n{compile_result.stderr}"
    try:
        for index in range(2):
            raw = os.urandom(FRAME_SIZE)
            run_analyzer(ANALYZER, raw, f"release-{index}")
            run_analyzer(strict_binary, raw, f"sanitized-{index}")
    finally:
        try:
            os.unlink(strict_binary)
        except FileNotFoundError:
            pass


def test_server_is_bash_based_and_references_required_tools():
    assert os.path.isfile(SERVER), f"Missing server script: {SERVER}"
    with open(SERVER, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    first_line = text.splitlines()[0] if text.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, "API server must be a Bash script"
    syntax = subprocess.run(["bash", "-n", SERVER], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"Bash syntax error: {syntax.stderr}"
    assert re.search(r"\bffmpeg\b", text), "Server script does not invoke ffmpeg"
    assert "frame_analyzer" in text, "Server script does not invoke frame_analyzer"
    assert not re.search(r"(^|[;&|[:space:]])(python3?|node|ruby|php)([[:space:]]|$)", text, re.MULTILINE), \
        "Server delegates implementation to a non-Bash runtime"


def test_api_unauthorized_missing_header():
    url = "http://127.0.0.1:9090/api/v1/analyze?time=2"
    try:
        response = requests.get(url, timeout=5)
        assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API server: {e}")


def test_api_unauthorized_invalid_header():
    url = "http://127.0.0.1:9090/api/v1/analyze?time=2"
    try:
        response = requests.get(url, headers={"Authorization": "Bearer wrong-key"}, timeout=5)
        assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API server: {e}")


def test_api_dynamic_frames_and_tool_pipeline():
    # Preserve the original fixed checks and add unpredictable sub-second queries.
    random_times = []
    while len(random_times) < 3:
        value = f"{(1000 + secrets.randbelow(7500)) / 1000:.3f}"
        if value not in random_times and value not in ("2.000", "5.000"):
            random_times.append(value)
    times = ["2", "5"] + random_times

    expected = {}
    for value in times:
        raw = extract_frame(value)
        expected[value] = {
            "checksum": sum(raw) % 256,
            "sha256": hashlib.sha256(raw).hexdigest(),
        }

    token = uuid.uuid4().hex
    analyzer_real = f"{ANALYZER}.verifier-real-{token}"
    ffmpeg = os.path.realpath("/usr/bin/ffmpeg")
    ffmpeg_real = f"{ffmpeg}.verifier-real-{token}"
    analyzer_log = f"/tmp/analyzer-calls-{token}"
    ffmpeg_log = f"/tmp/ffmpeg-calls-{token}"
    analyzer_wrapped = False
    ffmpeg_wrapped = False

    try:
        os.replace(ANALYZER, analyzer_real)
        analyzer_wrapped = True
        with open(ANALYZER, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"/usr/bin/sha256sum -- \"$1\" | /usr/bin/cut -d' ' -f1 >> {analyzer_log!r}\n")
            f.write(f"exec {analyzer_real!r} \"$@\"\n")
        os.chmod(ANALYZER, 0o755)

        os.replace(ffmpeg, ffmpeg_real)
        ffmpeg_wrapped = True
        with open(ffmpeg, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%q ' \"$@\" >> {ffmpeg_log!r}\n")
            f.write(f"printf '\\n' >> {ffmpeg_log!r}\n")
            f.write(f"exec {ffmpeg_real!r} \"$@\"\n")
        os.chmod(ffmpeg, 0o755)

        for value in times:
            url = f"http://127.0.0.1:9090/api/v1/analyze?time={value}"
            try:
                response = requests.get(url, headers=AUTH, timeout=15)
            except requests.exceptions.RequestException as e:
                pytest.fail(f"Failed to connect to API server for time={value}: {e}")
            assert response.status_code == 200, f"Expected 200 OK for time={value}, got {response.status_code}"
            assert "application/json" in response.headers.get("Content-Type", ""), \
                "Expected Content-Type: application/json"
            try:
                data = response.json()
            except json.JSONDecodeError:
                pytest.fail(f"Failed to parse JSON response. Raw response: {response.text}")
            assert "time" in data, "Missing 'time' in JSON response"
            assert str(data["time"]) == value, f"Expected time {value!r}, got {data['time']!r}"
            assert "checksum" in data, "Missing 'checksum' in JSON response"
            assert int(data["checksum"]) == expected[value]["checksum"], \
                f"Expected checksum {expected[value]['checksum']}, got {data['checksum']}"

        assert os.path.isfile(analyzer_log), "API never invoked /home/user/analyzer/frame_analyzer"
        with open(analyzer_log) as f:
            analyzed_hashes = [line.strip() for line in f if line.strip()]
        for value in times:
            assert expected[value]["sha256"] in analyzed_hashes, \
                f"Analyzer was not given the ffmpeg-extracted RGB24 frame for time={value}"

        assert os.path.isfile(ffmpeg_log), "API never invoked ffmpeg"
        with open(ffmpeg_log) as f:
            ffmpeg_calls = [line.strip() for line in f if line.strip()]
        assert len(ffmpeg_calls) >= len(times), "API did not invoke ffmpeg for every authorized request"
        relevant = [line for line in ffmpeg_calls if VIDEO in line and "rgb24" in line and "rawvideo" in line]
        assert len(relevant) >= len(times), "ffmpeg was not used to extract RGB24 raw frames from the test video"
        assert all(("-vframes" in line or "-frames:v" in line) and "1" in line for line in relevant), \
            "ffmpeg was not instructed to extract exactly one frame"
    finally:
        if ffmpeg_wrapped:
            try:
                os.unlink(ffmpeg)
            except FileNotFoundError:
                pass
            if os.path.exists(ffmpeg_real):
                os.replace(ffmpeg_real, ffmpeg)
        if analyzer_wrapped:
            try:
                os.unlink(ANALYZER)
            except FileNotFoundError:
                pass
            if os.path.exists(analyzer_real):
                os.replace(analyzer_real, ANALYZER)
        for path in (analyzer_log, ffmpeg_log):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
