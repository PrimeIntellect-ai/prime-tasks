#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time

import cv2
import numpy as np

VIDEO = "/app/deployment_monitor.mp4"
OUTPUT = "/home/user/red_frames.txt"


def count_solid_red_frames(path):
    capture = cv2.VideoCapture(path)
    assert capture.isOpened(), f"Could not open video {path}"
    count = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        # MP4 is lossy, so recognize frames whose decoded pixels are uniformly
        # near the requested solid-red BGR value.
        red = frame[:, :, 2]
        green = frame[:, :, 1]
        blue = frame[:, :, 0]
        if np.all(red >= 200) and np.all(green <= 50) and np.all(blue <= 50):
            count += 1
    capture.release()
    return count


def read_exact_integer(path):
    assert os.path.isfile(path), f"Output file {path} is missing"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content.isdigit() and "\n" not in content, f"Expected only an integer in {path}, got {content!r}"
    return int(content)


def analyzer_candidates():
    excluded = {
        os.path.realpath("/home/user/validate_manifests.py"),
        os.path.realpath("/home/user/forward.py"),
    }
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) in excluded or path == OUTPUT:
                continue
            if name.endswith(".py"):
                yield path, ["/usr/bin/python3", path]
            elif name.endswith(".sh"):
                yield path, ["/bin/bash", path]
            elif os.access(path, os.X_OK):
                yield path, [path]


def run_analyzer(command):
    invocations = [
        command,
        command + [VIDEO],
        command + [VIDEO, OUTPUT],
    ]
    for invocation in invocations:
        try:
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
            subprocess.run(invocation, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
        except (subprocess.TimeoutExpired, OSError):
            continue
        if os.path.isfile(OUTPUT):
            try:
                value = read_exact_integer(OUTPUT)
            except AssertionError:
                continue
            yield invocation, value


def test_red_frames_count_and_analysis_script():
    expected_original = count_solid_red_frames(VIDEO)
    assert expected_original > 0, "Diagnostic video unexpectedly contains no red frames"

    # Preserve the original assertion, but derive its answer from the supplied video.
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you run the video analysis?"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == str(expected_original), f"Expected exactly {expected_original} red frames, but got {content!r} in {OUTPUT}."

    candidates = list(analyzer_candidates())
    assert candidates, "No video-analysis script was found under /home/user"

    backup = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
    backup.close()
    alternate = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
    alternate.close()
    shutil.copy2(VIDEO, backup.name)

    writer = cv2.VideoWriter(alternate.name, cv2.VideoWriter_fourcc(*"mp4v"), 30, (100, 100))
    assert writer.isOpened(), "Could not create verifier video"
    alternate_red = secrets.randbelow(16) + 5
    red_indices = set(secrets.SystemRandom().sample(range(60), alternate_red))
    for index in range(60):
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        frame[:] = (0, 0, 255) if index in red_indices else (0, 255, 0)
        writer.write(frame)
    writer.release()
    expected_alternate = count_solid_red_frames(alternate.name)

    successful = None
    try:
        shutil.copy2(alternate.name, VIDEO)
        for path, command in candidates:
            for invocation, value in run_analyzer(command):
                if value == expected_alternate:
                    successful = (path, invocation)
                    break
            if successful:
                break

        assert successful is not None, "No submitted analysis script correctly analyzed a verifier-generated video"

        shutil.copy2(backup.name, VIDEO)
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        result = subprocess.run(successful[1], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
        assert result.returncode == 0, f"Analysis script failed on the deployment video: {result.stderr.decode(errors='replace')}"
        assert read_exact_integer(OUTPUT) == expected_original, "Analysis script did not reproduce the correct deployment-video count"
    finally:
        shutil.copy2(backup.name, VIDEO)
        for path in (backup.name, alternate.name):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_manifest_sanitiser_corpus():
    script_path = "/home/user/validate_manifests.py"
    assert os.path.isfile(script_path), f"Sanitiser script {script_path} is missing."

    clean_files = glob.glob("/app/corpus/clean/*.json")
    evil_files = glob.glob("/app/corpus/evil/*.json")
    assert len(clean_files) > 0, "Clean corpus is empty or missing."
    assert len(evil_files) > 0, "Evil corpus is empty or missing."

    clean_failed = []
    for clean_file in clean_files:
        result = subprocess.run(["/usr/bin/python3", script_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(clean_file))

    evil_failed = []
    for evil_file in evil_files:
        result = subprocess.run(["/usr/bin/python3", script_path, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(evil_file))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}{'...' if len(clean_failed) > 5 else ''}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed[:5])}{'...' if len(evil_failed) > 5 else ''}")
    assert not error_messages, "Adversarial corpus verification failed:\n" + "\n".join(error_messages)


def test_manifest_sanitiser_generated_paths():
    script_path = "/home/user/validate_manifests.py"
    cases = [
        ({"routes": []}, 0),
        ({"routes": [{"destination": "198.51.99.255"}, {"destination": "198.51.101.0"}]}, 0),
        ({"routes": [{"destination": "10.2.3.4"}, {"destination": "203.0.113.8"}]}, 0),
        ({"routes": [{"destination": f"198.51.100.{secrets.randbelow(256)}"}]}, 1),
        ({"routes": [{"destination": "192.0.2.1"}, {"destination": f"198.51.100.{secrets.randbelow(254) + 1}"}, {"destination": "10.0.0.1"}]}, 1),
    ]
    import json
    with tempfile.TemporaryDirectory(prefix="routing-inputs-") as directory:
        for index, (manifest, expected) in enumerate(cases):
            path = os.path.join(directory, f"case-{secrets.token_hex(6)}-{index}.json")
            with open(path, "w") as f:
                json.dump(manifest, f)
            result = subprocess.run(["/usr/bin/python3", script_path, path], capture_output=True, timeout=5)
            assert result.returncode == expected, f"Generated manifest {manifest!r} expected exit {expected}, got {result.returncode}"


def test_forward_script_and_cron():
    script_path = "/home/user/forward.py"
    assert os.path.isfile(script_path), f"Port forward script {script_path} is missing."

    syntax_check = subprocess.run(["/usr/bin/python3", "-m", "py_compile", script_path], capture_output=True)
    assert syntax_check.returncode == 0, f"Syntax error in {script_path}:\n{syntax_check.stderr.decode()}"

    crontab_check = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert crontab_check.returncode == 0, "Failed to read crontab. Has it been initialized for the user?"
    cron_lines = [line.strip() for line in crontab_check.stdout.splitlines() if line.strip() and not line.startswith("#")]
    found_cron = False
    for line in cron_lines:
        if "* * * * *" in line and script_path in line and "python3" in line:
            found_cron = True
            break
    assert found_cron, f"Could not find the expected cron job running {script_path} every minute (* * * * *). Found crontab: {crontab_check.stdout}"

    # Exercise the forwarder end-to-end in both directions.
    subprocess.run(["pkill", "-f", "^.*python3 .*\/home\/user\/forward.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    upstream.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    upstream.bind(("127.0.0.1", 9999))
    upstream.listen(1)
    server_errors = []

    def serve():
        try:
            upstream.settimeout(10)
            connection, address = upstream.accept()
            with connection:
                connection.settimeout(5)
                request = connection.recv(4096)
                assert request == b"client-to-upstream-" + payload
                connection.sendall(b"upstream-to-client-" + payload)
        except BaseException as exc:
            server_errors.append(exc)

    payload = secrets.token_bytes(32)
    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    process = subprocess.Popen(["/usr/bin/python3", script_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
    client = None
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            assert process.poll() is None, f"Forwarder exited early: {process.stderr.read().decode(errors='replace')}"
            try:
                client = socket.create_connection(("127.0.0.1", 8888), timeout=0.5)
                break
            except OSError:
                time.sleep(0.1)
        assert client is not None, "Forwarder did not listen on 127.0.0.1:8888"
        with client:
            client.settimeout(5)
            client.sendall(b"client-to-upstream-" + payload)
            expected = b"upstream-to-client-" + payload
            received = b""
            while len(received) < len(expected):
                part = client.recv(4096)
                assert part, "Forwarder closed the connection before returning upstream data"
                received += part
            assert received == expected, "Forwarder corrupted or failed to return upstream TCP data"
        thread.join(timeout=6)
        assert not thread.is_alive(), "Upstream did not receive traffic through the forwarder"
        assert not server_errors, f"Upstream forwarding test failed: {server_errors!r}"
    finally:
        upstream.close()
        try:
            os.killpg(process.pid, 15)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, 9)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
