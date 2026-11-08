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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import socket
import string
import subprocess
import wave

import pytest
import requests

NGINX_URL = "http://127.0.0.1:8080/api/transcribe"
BACKEND_URL = "http://127.0.0.1:9090/transcribe"
AUTH = ("ci_runner", "build_pass_2024")
AUDIO_PATH = "/app/build_audio_test.wav"
PAYLOAD = {"filepath": AUDIO_PATH}
SOURCE_DIR = "/home/user/workspace/audio_service"
SCRIPT_PATH = "/home/user/workspace/test_pipeline.sh"
LOG_PATH = "/home/user/workspace/result.log"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(pid))
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def process_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def install_audio_fixture():
    sample = "/opt/whisper.cpp/samples/jfk.wav"
    if os.path.isfile(sample):
        try:
            with wave.open(sample, "rb") as wav:
                assert wav.getnframes() > 0
            shutil.copyfile(sample, AUDIO_PATH)
            return "jfk"
        except (wave.Error, AssertionError):
            pass

    # A valid, non-empty WAV is still preferable to the empty file from setup.
    # Its semantic answer is silence, rather than the fixed phrase used by the
    # old verifier.
    with wave.open(AUDIO_PATH, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\0\0" * 32000)
    return "silence"


FIXTURE_KIND = install_audio_fixture()
_direct_response = None


def direct_response():
    global _direct_response
    if _direct_response is None:
        _direct_response = requests.post(BACKEND_URL, json=PAYLOAD, timeout=180)
    return _direct_response


def assert_transcription_response(response):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "transcript" in data, "Response JSON missing 'transcript' key."
    assert isinstance(data["transcript"], str), "transcript must be a string"
    return data


def test_01_real_processes_own_both_listeners():
    nginx_pids = listening_pids(8080)
    backend_pids = listening_pids(9090)
    assert nginx_pids, "Nothing is listening on 127.0.0.1:8080"
    assert backend_pids, "Nothing is listening on 127.0.0.1:9090"

    nginx_exes = [process_exe(pid) for pid in nginx_pids]
    assert any(os.path.basename(exe) == "nginx" for exe in nginx_exes), (
        f"Port 8080 is not owned by nginx: {nginx_exes}"
    )

    backend_exes = [process_exe(pid) for pid in backend_pids]
    workspace = os.path.realpath(SOURCE_DIR) + os.sep
    candidates = [exe for exe in backend_exes if exe.startswith(workspace)]
    assert candidates, f"Port 9090 is not owned by the compiled workspace service: {backend_exes}"
    for exe in candidates:
        with open(exe, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Backend is not a compiled ELF executable: {exe}"

    cmake = open(os.path.join(SOURCE_DIR, "CMakeLists.txt"), errors="replace").read().lower()
    assert "whisper" in cmake, "CMakeLists.txt does not link/configure whisper.cpp"
    marker_found = False
    for exe in candidates:
        result = subprocess.run(
            ["nm", "-C", exe], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=20
        )
        if "whisper_" in result.stdout.lower() or "whisper.cpp" in result.stdout.lower():
            marker_found = True
            break
        with open(exe, "rb") as f:
            blob = f.read()
        if b"whisper_" in blob.lower() or b"whisper.cpp" in blob.lower():
            marker_found = True
            break
    assert marker_found, "Running backend has no evidence that whisper.cpp is linked and used"


def test_02_audio_chunk_pool_is_memory_clean():
    source = os.path.join(SOURCE_DIR, "AudioChunkPool.cpp")
    assert os.path.isfile(source), f"Missing {source}"

    harness = "/tmp/audio_pool_harness.cpp"
    binary = "/tmp/audio_pool_harness"
    with open(harness, "w") as f:
        f.write(f'''#include "{source}"
int main() {{
    for (int outer = 0; outer < 100; ++outer) {{
        AudioChunkPool pool;
        for (int i = 0; i < 100; ++i) pool.allocate();
    }}
    return 0;
}}
''')

    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O0", "-g", harness, "-o", binary],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert compiled.returncode == 0, f"AudioChunkPool could not be exercised:\n{compiled.stdout}"

    checked = subprocess.run(
        ["valgrind", "--quiet", "--leak-check=full",
         "--show-leak-kinds=all", "--errors-for-leak-kinds=definite,indirect,possible",
         "--error-exitcode=99", binary],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert checked.returncode == 0, f"Valgrind found a leak or invalid memory access:\n{checked.stdout}"


def test_03_backend_rejects_inputs_it_cannot_transcribe():
    token = "".join(random.choice(string.ascii_lowercase) for _ in range(20))
    missing = f"/tmp/{token}.wav"
    response = requests.post(BACKEND_URL, json={"filepath": missing}, timeout=15)
    assert response.status_code >= 400, "Backend returned success for a nonexistent randomized file"

    malformed = f"/tmp/{token}-malformed.wav"
    with open(malformed, "wb") as f:
        f.write(os.urandom(257))
    try:
        response = requests.post(BACKEND_URL, json={"filepath": malformed}, timeout=30)
        assert response.status_code >= 400, "Backend returned success for malformed random data"
    finally:
        os.unlink(malformed)


def test_04_cpp_backend_transcribes_valid_audio_directly():
    data = assert_transcription_response(direct_response())
    transcript = data["transcript"].lower()
    if FIXTURE_KIND == "jfk":
        for word in ("fellow", "americans", "country"):
            assert word in transcript, f"Expected word '{word}' from the JFK audio, got: {transcript}"
    else:
        canned = ("mobile", "build", "alpha", "seven", "two", "successful")
        assert not all(word in transcript for word in canned), (
            "Silent audio produced the old verifier's fixed canned transcript"
        )


def test_05_nginx_unauthenticated_rejected():
    try:
        response = requests.post(NGINX_URL, json=PAYLOAD, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx proxy at {NGINX_URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    wrong = requests.post(NGINX_URL, json=PAYLOAD, auth=(AUTH[0], "wrong-password"), timeout=5)
    assert wrong.status_code == 401, f"Expected wrong credentials to be rejected, got {wrong.status_code}"


def test_06_nginx_authenticated_success_and_forwarding():
    try:
        response = requests.post(NGINX_URL, json=PAYLOAD, auth=AUTH, timeout=180)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx proxy at {NGINX_URL}: {e}")

    proxied = assert_transcription_response(response)
    direct = assert_transcription_response(direct_response())
    assert proxied["transcript"].strip() == direct["transcript"].strip(), (
        "Nginx response does not match the C++ backend response"
    )


def test_07_pipeline_script_exists_runs_and_writes_result():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    script = open(SCRIPT_PATH, errors="replace").read()
    assert os.access(SCRIPT_PATH, os.X_OK) or "curl" in script, "Script should contain curl command."
    assert "curl" in script, "Pipeline script must invoke curl"
    assert NGINX_URL in script, "Pipeline script must call the authenticated Nginx endpoint"
    assert AUDIO_PATH in script, "Pipeline script must submit /app/build_audio_test.wav"

    try:
        os.unlink(LOG_PATH)
    except FileNotFoundError:
        pass

    run = subprocess.run(
        ["bash", SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=240
    )
    assert run.returncode == 0, f"test_pipeline.sh failed:\n{run.stdout}"
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} is missing after running the pipeline script."

    content = open(LOG_PATH).read()
    try:
        data = json.loads(content)
    except ValueError:
        pytest.fail(f"Expected raw JSON in {LOG_PATH}, got: {content}")
    assert "transcript" in data, f"{LOG_PATH} JSON missing 'transcript' key."
    assert isinstance(data["transcript"], str)

    direct = assert_transcription_response(direct_response())
    assert data["transcript"].strip() == direct["transcript"].strip(), (
        "result.log does not contain the backend's transcription of the supplied audio"
    )
    transcript = data["transcript"].lower()
    if FIXTURE_KIND == "jfk":
        for word in ("fellow", "americans", "country"):
            assert word in transcript, f"Expected word '{word}' not found in log transcript: {transcript}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
