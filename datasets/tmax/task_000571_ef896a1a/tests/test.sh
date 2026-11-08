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
import signal
import socket
import struct
import subprocess
import time
import wave

import numpy as np
import pytest
import requests

SOURCE = "/home/user/pipeline.go"
WAV_PATH = "/app/signal_data.wav"
BINARY = "/tmp/pipeline_submission"
PROC = None
ORIGINAL_WAV = None


def stop_listeners(ports=(8080, 9090)):
    wanted = {f"{port:04X}" for port in ports}
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = fields[1].rsplit(":", 1)[-1].upper()
                        if local_port in wanted:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_servers(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Compiled Go application exited early with status {proc.returncode}")
        http_ready = tcp_ready = False
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                http_ready = True
        except OSError:
            pass
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                tcp_ready = True
        except OSError:
            pass
        if http_ready and tcp_ready:
            return
        time.sleep(0.1)
    pytest.fail("Compiled Go application did not listen on both required ports")


def start_submission():
    global PROC
    PROC = subprocess.Popen(
        [BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_servers(PROC)


def stop_submission():
    global PROC
    if PROC is not None and PROC.poll() is None:
        PROC.terminate()
        try:
            PROC.wait(timeout=2)
        except subprocess.TimeoutExpired:
            PROC.kill()
            PROC.wait(timeout=2)
    PROC = None
    stop_listeners()


@pytest.fixture(scope="session", autouse=True)
def compiled_submission():
    global ORIGINAL_WAV
    with open(WAV_PATH, "rb") as f:
        ORIGINAL_WAV = f.read()

    stop_listeners()
    result = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"pipeline.go did not compile:\n{result.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    start_submission()
    try:
        yield
    finally:
        stop_submission()
        if ORIGINAL_WAV is not None:
            with open(WAV_PATH, "wb") as f:
                f.write(ORIGINAL_WAV)


def test_00_source_code_exists():
    """Verify that the Go source code was saved at the correct location."""
    assert os.path.exists(SOURCE), f"Expected Go source code at {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"Expected {SOURCE} to be a file."


def test_01_http_server_valid_request():
    """Verify that the HTTP server responds correctly to a valid request."""
    url = "http://127.0.0.1:8080/sequence"
    headers = {"Authorization": "Bearer bio-perf-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to {url} failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    expected_body = ">Extracted_Sequence\nAGCTA"
    assert response.text.strip() == expected_body, f"Expected response body '{expected_body}', got '{response.text.strip()}'"


def test_02_http_server_invalid_request():
    """Verify the HTTP server responds with 401 or 404 for an invalid token."""
    url = "http://127.0.0.1:8080/sequence"
    headers = {"Authorization": "Bearer invalid-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to {url} failed: {e}")

    assert response.status_code in (401, 404), f"Expected HTTP 401 or 404 for invalid token, got {response.status_code}"


def test_03_tcp_server_response():
    """Verify the TCP server responds correctly to the PING command."""
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=5) as sock:
            sock.sendall(b"PING\n")
            data = sock.recv(4096)
    except Exception as e:
        pytest.fail(f"TCP connection or communication with 127.0.0.1:9090 failed: {e}")

    response_text = data.decode("utf-8")
    expected_response = ">Extracted_Sequence\nAGCTA\n"
    assert response_text.strip() == expected_response.strip(), f"Expected TCP response '{expected_response.strip()}', got '{response_text.strip()}'"


def make_challenge_wav():
    rate = 44100
    size = 4410
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    letters = list("ACGTACGT")
    rng.shuffle(letters)
    letters.extend(rng.choice(list("ACGT"), size=4).tolist())
    centers = {"A": 1000, "C": 1500, "G": 2000, "T": 2500}
    offsets = np.array([-40, -20, 0, 20, 40])

    windows = []
    # Include windows that must be ignored as well as randomized mapped windows.
    insertion_points = {2: "silence", 7: "outside"}
    for i in range(len(letters) + len(insertion_points)):
        if i in insertion_points:
            if insertion_points[i] == "silence":
                windows.append(np.zeros(size, dtype=np.float64))
            else:
                t = np.arange(size) / rate
                windows.append(0.78 * np.sin(2 * np.pi * 3300 * t + 0.31))
            continue

        letter_index = i - sum(1 for point in insertion_points if point < i)
        letter = letters[letter_index]
        primary = centers[letter] + int(rng.choice(offsets))
        secondary_choices = [1000, 1500, 2000, 2500, 3100]
        secondary_choices = [f for f in secondary_choices if abs(f - primary) > 100]
        secondary = int(rng.choice(secondary_choices))
        t = np.arange(size) / rate
        phase1, phase2 = rng.uniform(0, 2 * np.pi, size=2)
        samples = (
            0.72 * np.sin(2 * np.pi * primary * t + phase1)
            + 0.14 * np.sin(2 * np.pi * secondary * t + phase2)
            + rng.normal(0, 0.008, size=size)
        )
        windows.append(samples)

    pcm = np.int16(np.clip(np.concatenate(windows), -1, 1) * 32767)
    with wave.open(WAV_PATH, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.astype("<i2").tobytes())


def derive_expected_from_wav():
    with wave.open(WAV_PATH, "rb") as src:
        assert src.getnchannels() == 1
        assert src.getsampwidth() == 2
        rate = src.getframerate()
        samples = np.frombuffer(src.readframes(src.getnframes()), dtype="<i2").astype(np.float64)

    sequence = []
    for start in range(0, len(samples) - 4409, 4410):
        window = samples[start:start + 4410]
        spectrum = np.abs(np.fft.rfft(window))
        peak_bin = int(np.argmax(spectrum))
        peak_magnitude = float(spectrum[peak_bin])
        frequency = peak_bin * rate / 4410
        if peak_magnitude < 1_000_000:
            continue
        for center, letter in ((1000, "A"), (1500, "C"), (2000, "G"), (2500, "T")):
            if abs(frequency - center) <= 50:
                sequence.append(letter)
                break
    return ">Extracted_Sequence\n" + "".join(sequence)


def test_04_reextracts_changed_wav_with_fft_dominant_peaks():
    stop_submission()
    make_challenge_wav()
    expected = derive_expected_from_wav()
    assert expected != ">Extracted_Sequence\nAGCTA"
    start_submission()

    response = requests.get(
        "http://127.0.0.1:8080/sequence",
        headers={"Authorization": "Bearer bio-perf-token"},
        timeout=5,
    )
    assert response.status_code == 200
    assert response.text.strip() == expected

    chunks = []
    with socket.create_connection(("127.0.0.1", 9090), timeout=5) as sock:
        sock.sendall(b"PING\n")
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    assert b"".join(chunks).decode("utf-8").strip() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
