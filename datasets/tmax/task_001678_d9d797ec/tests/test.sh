#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import signal
import subprocess
import time

import h5py
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8000/solution"
DATA_PATH = "/app/sequence_data.h5"
PORT_HEX = format(8000, "04X")


def get_solution(retries=20):
    last_error = None
    for _ in range(retries):
        try:
            response = requests.get(URL, timeout=2)
            assert response.status_code == 200, (
                f"Expected status code 200, got {response.status_code}"
            )
            try:
                data = response.json()
            except ValueError:
                pytest.fail(
                    f"Response is not valid JSON. Response text: {response.text}"
                )
            assert "S" in data, f"Response JSON missing key 'S'. Got: {data}"
            actual_s = data["S"]
            assert isinstance(actual_s, (int, float)) and not isinstance(actual_s, bool), (
                f"Value of 'S' must be a number, got {type(actual_s)}"
            )
            return actual_s
        except (requests.exceptions.RequestException, AssertionError) as exc:
            last_error = exc
            time.sleep(0.25)
    pytest.fail(f"Failed to obtain a valid response from {URL}: {last_error}")


def listening_socket_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as fh:
                next(fh, None)
                for line in fh:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == PORT_HEX and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    return inodes


def listener_pids():
    inodes = listening_socket_inodes()
    found = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit("/", 1)[1])
        for fd in glob.glob(proc_dir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                found.add(pid)
                break
    return found


def capture_server_command():
    pids = listener_pids()
    assert pids, "No process is listening on port 8000"
    pid = min(pids)
    with open(f"/proc/{pid}/cmdline", "rb") as fh:
        argv = [part.decode("utf-8", "surrogateescape") for part in fh.read().split(b"\0") if part]
    assert argv, f"Could not determine command line for server process {pid}"
    executable = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as fh:
        for item in fh.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return executable, argv, cwd, env


def stop_server():
    deadline = time.time() + 5
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.15)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the submitted server for behavioral testing"


def start_server(command):
    executable, argv, cwd, env = command
    subprocess.Popen(
        argv,
        executable=executable,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def write_signal(frequency):
    sample_rate = 1000.0
    t = np.arange(2000, dtype=np.float64) / sample_rate
    # A weaker off-frequency component prevents a trivial all-zero/single-sample shortcut.
    signal_data = np.sin(2 * np.pi * frequency * t)
    signal_data += 0.17 * np.sin(2 * np.pi * (frequency + 7) * t + 0.31)
    with h5py.File(DATA_PATH, "w") as h5:
        h5.create_dataset("/nanopore/signal_1", data=signal_data)


def expected_from_file():
    with h5py.File(DATA_PATH, "r") as h5:
        samples = np.asarray(h5["/nanopore/signal_1"])
    spectrum = np.abs(np.fft.rfft(samples))
    spectrum[0] = 0
    dominant = np.fft.rfftfreq(samples.size, d=1.0 / 1000.0)[int(np.argmax(spectrum))]
    # 15 = Vmax*S^2.5 / (100 + S^2.5)
    power = 1500.0 / (dominant - 15.0)
    return round(power ** (1.0 / 2.5), 3)


def test_solution_endpoint_and_computation():
    # Preserve all original endpoint and fixed-instance assertions.
    actual_s = get_solution(retries=5)
    expected_s = 4.502
    assert round(actual_s, 3) == expected_s, f"Expected S to be {expected_s}, but got {actual_s}"

    command = capture_server_command()
    backup = f"/tmp/sequence_data.{os.getpid()}.h5"
    shutil.copy2(DATA_PATH, backup)
    rng = secrets.SystemRandom()
    frequencies = rng.sample([f for f in range(24, 421) if f not in (43, 50, 57)], 2)

    try:
        stop_server()
        for frequency in frequencies:
            write_signal(frequency)
            expected = expected_from_file()
            start_server(command)
            actual = get_solution()
            assert round(actual, 3) == expected, (
                f"For a signal whose FFT-derived dominant frequency is {frequency} Hz, "
                f"expected S={expected}, but got {actual}"
            )
            stop_server()
    finally:
        try:
            stop_server()
        except Exception:
            pass
        shutil.copy2(backup, DATA_PATH)
        os.unlink(backup)
        start_server(command)
        # Leave the required service running against the original input.
        restored = get_solution()
        assert round(restored, 3) == expected_s
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
