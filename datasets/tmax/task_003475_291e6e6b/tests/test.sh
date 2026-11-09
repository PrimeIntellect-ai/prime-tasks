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
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time
import uuid

import pytest
import requests

PIPELINE = "/home/user/pipeline"
PORT = 9090
SERVER = os.path.join(PIPELINE, "audio_server")


def listener_inodes():
    result = set()
    port_hex = f"{PORT:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[1] == port_hex:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_existing_listeners():
    inodes = listener_inodes()
    if not inodes:
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGKILL)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    deadline = time.time() + 3
    while listener_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(), "Could not clear the pre-existing listener on port 9090"


def listening_addresses():
    addresses = []
    port_hex = f"{PORT:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, port = fields[1].split(":")
                    if fields[3] == "0A" and port == port_hex:
                        addresses.append((table, address))
        except FileNotFoundError:
            pass
    return addresses


def wait_for_server(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, "audio_server exited before accepting connections"
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Compiled audio_server did not listen on 127.0.0.1:9090")


def test_complete_pipeline():
    mock_path = os.path.join(PIPELINE, "telemetry_mock.c")
    assert os.path.isfile(mock_path), f"File {mock_path} is missing. Did you implement the test mock?"

    kill_existing_listeners()

    # Force make all to rebuild every supplied C artifact rather than accepting
    # files left behind by an unrelated process.
    for name in ("server.o", "utils.o", "test.o", "telemetry_mock.o",
                 "server", "audio_server", "test_suite"):
        path = os.path.join(PIPELINE, name)
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make", "all"], cwd=PIPELINE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"make all failed:\n{build.stdout}"

    assert os.path.isfile(SERVER), f"File {SERVER} is missing. Did you successfully compile the application?"
    assert os.access(SERVER, os.X_OK), "audio_server is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audio_server is not a compiled ELF application"

    symbols = subprocess.run(
        ["nm", SERVER], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert symbols.returncode == 0, f"Unable to inspect audio_server:\n{symbols.stdout}"
    assert re.search(r"\bdo_nothing$", symbols.stdout, re.MULTILINE), \
        "audio_server was not linked with the required utils module"

    test_suite = os.path.join(PIPELINE, "test_suite")
    assert os.path.isfile(test_suite) and os.access(test_suite, os.X_OK), \
        "make all did not build an executable test_suite"
    telemetry_log = os.path.join(PIPELINE, "telemetry.log")
    try:
        os.remove(telemetry_log)
    except FileNotFoundError:
        pass
    suite = subprocess.run(
        [test_suite], cwd=PIPELINE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert suite.returncode == 0, f"test_suite failed:\n{suite.stdout}"
    assert os.path.isfile(telemetry_log), "test_suite did not create telemetry.log"
    with open(telemetry_log) as f:
        assert f.read() == "test_event", "test_suite did not log test_event exactly"

    # Exercise telemetry_mock.c independently with a verifier-generated event.
    event = "verifier_" + uuid.uuid4().hex
    harness_c = "/tmp/telemetry_harness.c"
    harness = "/tmp/telemetry_harness"
    with open(harness_c, "w") as f:
        f.write('#include <stdlib.h>\n'
                'int send_telemetry(const char *event);\n'
                'int main(int argc, char **argv) {\n'
                '  if (argc != 2) return 2;\n'
                '  return send_telemetry(argv[1]);\n'
                '}\n')
    compile_mock = subprocess.run(
        ["gcc", "-Wall", "-o", harness, harness_c, mock_path],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert compile_mock.returncode == 0, \
        f"telemetry_mock.c failed to compile with the interface:\n{compile_mock.stdout}"
    os.remove(telemetry_log)
    mock_run = subprocess.run(
        [harness, event], cwd=PIPELINE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert mock_run.returncode == 0, "send_telemetry did not return 0"
    assert os.path.isfile(telemetry_log), "send_telemetry did not create telemetry.log"
    with open(telemetry_log) as f:
        assert f.read() == event, "send_telemetry did not write the supplied event exactly"

    expected_text = subprocess.check_output(
        ["/usr/local/bin/whisper", "/app/voicemail.wav"],
        text=True, timeout=15
    ).strip()
    assert expected_text, "The provided audio artifact produced no transcript"

    proc = subprocess.Popen(
        [SERVER], cwd=PIPELINE, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    try:
        wait_for_server(proc)
        addresses = listening_addresses()
        assert addresses, "No listener was found on port 9090"
        assert all(table == "/proc/net/tcp" and address == "0100007F"
                   for table, address in addresses), \
            f"audio_server must bind exactly to 127.0.0.1, found {addresses}"

        try:
            response = requests.get("http://127.0.0.1:9090/health", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the audio_server on 127.0.0.1:9090. Is it running? Error: {e}")
        assert response.status_code == 200, f"Expected 200 OK for /health, got {response.status_code}"
        assert "OK" in response.text, f"Expected 'OK' in /health response body, got: {response.text}"
        assert response.raw.version == 11, "The server must respond using HTTP/1.1"
        assert response.text == "OK", f"Expected exact /health body 'OK', got {response.text!r}"

        try:
            response = requests.get("http://127.0.0.1:9090/transcript", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the audio_server on 127.0.0.1:9090. Error: {e}")
        assert response.status_code == 401, f"Expected 401 Unauthorized for /transcript without auth, got {response.status_code}"

        invalid = requests.get(
            "http://127.0.0.1:9090/transcript",
            headers={"Authorization": "Bearer wrong_token"}, timeout=2
        )
        assert invalid.status_code == 401, \
            f"Expected 401 Unauthorized for invalid auth, got {invalid.status_code}"

        headers = {"Authorization": "Bearer ci_pipeline_token"}
        try:
            response = requests.get("http://127.0.0.1:9090/transcript", headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the audio_server on 127.0.0.1:9090. Error: {e}")
        assert response.status_code == 200, f"Expected 200 OK for /transcript with valid auth, got {response.status_code}"

        actual_clean = ''.join(c.lower() for c in response.text if c.isalnum() or c.isspace()).strip()
        expected_clean = ''.join(c.lower() for c in expected_text if c.isalnum() or c.isspace()).strip()
        assert expected_clean in actual_clean, \
            f"Expected transcript to contain '{expected_clean}', but got '{actual_clean}'"
        assert response.raw.version == 11, "The server must respond using HTTP/1.1"
        assert response.text == expected_text, \
            f"Expected exact transcript {expected_text!r}, got {response.text!r}"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
