#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import shutil
import signal
import subprocess
import threading
import time

import requests

SERVER_SOURCE = "/home/user/server.go"
SERVER_BINARY = "/tmp/submission-server"
AUDIO_PATH = "/app/dataset.wav"
BASE_URL = "http://127.0.0.1:8080"


def ffprobe_duration(path):
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path,
    ]
    try:
        output = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode().strip()
        return float(output)
    except Exception as e:
        raise RuntimeError(f"Failed to extract duration from {path}: {e}")


def expected_metrics(path):
    duration = ffprobe_duration(path)
    return {
        "duration": duration,
        "z_score": (duration - 10.0) / 2.0,
        "posterior_mean": (2.5 + duration) / 1.25,
    }


def install_audio(source):
    staging = AUDIO_PATH + ".verifier-new"
    shutil.copyfile(source, staging)
    os.replace(staging, AUDIO_PATH)


def assert_metrics_response(resp, expected):
    assert resp.status_code == 200, (
        f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
    )
    try:
        data = resp.json()
    except ValueError:
        raise AssertionError(f"Response is not valid JSON. Response: {resp.text}")

    assert isinstance(data, dict), "JSON response must be an object"
    assert set(data.keys()) == {"duration", "z_score", "posterior_mean"}, (
        f"JSON must contain exactly duration, z_score, and posterior_mean; got {sorted(data.keys())}"
    )

    for key in ("duration", "z_score", "posterior_mean"):
        assert isinstance(data[key], float), f"{key} must be encoded as a floating-point number"

    assert math.isclose(data["duration"], expected["duration"], rel_tol=1e-3), \
        f"Expected duration approx {expected['duration']}, got {data['duration']}"
    assert math.isclose(data["z_score"], expected["z_score"], rel_tol=1e-3), \
        f"Expected z_score approx {expected['z_score']}, got {data['z_score']}"
    assert math.isclose(data["posterior_mean"], expected["posterior_mean"], rel_tol=1e-3), \
        f"Expected posterior_mean approx {expected['posterior_mean']}, got {data['posterior_mean']}"


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(proc):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            raise AssertionError(
                f"Compiled Go server exited early with status {proc.returncode}. "
                f"stdout={out!r}, stderr={err!r}"
            )
        try:
            requests.get(BASE_URL + "/metrics", timeout=0.4)
            return
        except requests.RequestException as e:
            last_error = e
            time.sleep(0.1)
    raise AssertionError(f"Compiled Go server did not listen on 127.0.0.1:8080: {last_error}")


def switch_after_first_dataset_open(replacement):
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_OPEN = 0x20
    fd = libc.inotify_init1(0)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    wd = libc.inotify_add_watch(fd, b"/app", IN_OPEN)
    if wd < 0:
        err = ctypes.get_errno()
        os.close(fd)
        raise OSError(err, "inotify_add_watch failed")

    ready = threading.Event()
    switched = threading.Event()

    def watcher():
        ready.set()
        try:
            while True:
                buf = os.read(fd, 4096)
                offset = 0
                while offset + 16 <= len(buf):
                    wd_value = int.from_bytes(buf[offset:offset+4], "little", signed=True)
                    mask = int.from_bytes(buf[offset+4:offset+8], "little")
                    name_len = int.from_bytes(buf[offset+12:offset+16], "little")
                    raw_name = buf[offset+16:offset+16+name_len]
                    name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                    offset += 16 + name_len
                    if wd_value == wd and (mask & IN_OPEN) and name == "dataset.wav":
                        install_audio(replacement)
                        switched.set()
                        return
        finally:
            os.close(fd)

    thread = threading.Thread(target=watcher, daemon=True)
    thread.start()
    assert ready.wait(1), "Failed to start reproducibility watcher"
    return switched, thread


def test_metrics_endpoint():
    assert os.path.isfile(SERVER_SOURCE), f"Missing required Go source file {SERVER_SOURCE}"
    with open(SERVER_SOURCE, "rb") as f:
        source_prefix = f.read(256)
    assert b"package main" in source_prefix, f"{SERVER_SOURCE} is not a Go main package"

    build = subprocess.run(
        ["go", "build", "-o", SERVER_BINARY, SERVER_SOURCE],
        cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert build.returncode == 0, f"server.go does not build as Go code:\n{build.stderr}"

    original = "/tmp/verifier-original.wav"
    fixture_a = "/tmp/verifier-a.wav"
    fixture_b = "/tmp/verifier-b.wav"
    shutil.copyfile(AUDIO_PATH, original)
    subprocess.check_call([
        "ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
        "sine=frequency=700:duration=2.25", fixture_a,
    ])
    subprocess.check_call([
        "ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
        "sine=frequency=1200:duration=4.75", fixture_b,
    ])

    proc = None
    try:
        kill_port_8080_listeners()
        install_audio(original)
        proc = subprocess.Popen(
            [SERVER_BINARY], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        wait_for_server(proc)

        # Preserve the original fixture/value assertions.
        install_audio(original)
        assert_metrics_response(
            requests.get(BASE_URL + "/metrics", timeout=5),
            expected_metrics(original),
        )

        # The same running process must dynamically re-extract changed audio.
        for fixture in (fixture_a, fixture_b):
            install_audio(fixture)
            assert_metrics_response(
                requests.get(BASE_URL + "/metrics", timeout=5),
                expected_metrics(fixture),
            )

        # There must be no additional successful endpoints or methods.
        for path in ("/", "/other", "/metrics/"):
            resp = requests.get(BASE_URL + path, timeout=5)
            assert resp.status_code >= 400, f"Unexpected extra GET endpoint {path}: HTTP {resp.status_code}"
        resp = requests.post(BASE_URL + "/metrics", timeout=5)
        assert resp.status_code >= 400, f"POST /metrics must not be exposed: HTTP {resp.status_code}"

        # Replace dataset.wav immediately after its first open. A compliant handler
        # extracts once from fixture A and again from fixture B, detects inequality,
        # and returns HTTP 500. A one-extraction implementation continues with 200.
        install_audio(fixture_a)
        switched, watcher = switch_after_first_dataset_open(fixture_b)
        resp = requests.get(BASE_URL + "/metrics", timeout=8)
        assert switched.wait(3), "The request did not dynamically open /app/dataset.wav"
        watcher.join(timeout=1)
        assert resp.status_code == 500, (
            "Expected HTTP 500 when dataset.wav changed between the two required "
            f"duration extractions, got {resp.status_code}: {resp.text}"
        )
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        install_audio(original)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
