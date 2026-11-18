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
import subprocess
import time
import wave
from pathlib import Path

import numpy as np
import pytest
import requests
from scipy.io import wavfile

SCRIPT_PATH = "/home/user/start_server.sh"
PDB_PATH = Path("/app/molecule.pdb")
WAV_PATH = Path("/app/vibration.wav")
URL = "http://127.0.0.1:8080/features"
PORT = 8080


def expected_atom_count(path):
    count = 0
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("ATOM") and (len(line) == 4 or not line[4].isalnum() and line[4] != "_"):
                count += 1
    return count


def expected_peak_frequency(path):
    sample_rate, samples = wavfile.read(path)
    samples = np.asarray(samples)
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    samples = samples.astype(np.float64)
    spectrum = np.abs(np.fft.rfft(samples))
    frequencies = np.fft.rfftfreq(samples.size, d=1.0 / sample_rate)
    return int(round(float(frequencies[int(np.argmax(spectrum))])))


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def stop_port_listener():
    pids = listener_pids(PORT)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(20):
        if not listener_pids(PORT):
            return
        time.sleep(0.1)
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_feature_response(response, expected_frequency, expected_atoms):
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type.lower(), f"Expected Content-Type: application/json, got {content_type}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Got: {response.text}")
    assert "peak_frequency_hz" in data, "JSON response missing 'peak_frequency_hz' key."
    assert "atom_count" in data, "JSON response missing 'atom_count' key."
    assert data["peak_frequency_hz"] == expected_frequency, (
        f"Expected peak_frequency_hz to be {expected_frequency}, got {data['peak_frequency_hz']}"
    )
    assert data["atom_count"] == expected_atoms, (
        f"Expected atom_count to be {expected_atoms}, got {data['atom_count']}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_server_response_and_sequential_requests():
    original_pdb = PDB_PATH.read_bytes()
    original_wav = WAV_PATH.read_bytes()
    process = None

    try:
        stop_port_listener()

        pdb_lines = [
            "REMARK dynamic verifier input\n",
            "HETATM    1  O   HOH A   1\n",
            "ATOMX     2  C   BAD A   1\n",
            " atom     3  C   BAD A   1\n",
        ]
        for index in range(1, 8):
            pdb_lines.append(f"ATOM  {index:5d}  CA  GLY A {index:3d}      10.000  10.000  10.000\n")
        pdb_lines.append("END\n")
        PDB_PATH.write_text("".join(pdb_lines), encoding="utf-8")

        sample_rate = 44100
        duration = 2
        t = np.arange(sample_rate * duration, dtype=np.float64) / sample_rate
        signal_data = 0.75 * np.sin(2 * np.pi * 523 * t) + 0.15 * np.sin(2 * np.pi * 1200 * t)
        pcm = np.asarray(np.round(signal_data * 32767), dtype="<i2")
        with wave.open(str(WAV_PATH), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(sample_rate)
            output.writeframes(pcm.tobytes())

        expected_atoms = expected_atom_count(PDB_PATH)
        expected_frequency = expected_peak_frequency(WAV_PATH)

        process = subprocess.Popen(
            [SCRIPT_PATH],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        first_response = None
        for _ in range(20):
            try:
                candidate = requests.get(URL, timeout=1)
                if candidate.status_code == 200:
                    first_response = candidate
                    break
            except requests.exceptions.RequestException:
                pass
            time.sleep(0.25)

        assert first_response is not None, f"Failed to connect to the server at {URL} after starting {SCRIPT_PATH}."
        assert_feature_response(first_response, expected_frequency, expected_atoms)

        # Exercise the same running service repeatedly; it must survive each request.
        for _ in range(3):
            response = requests.get(URL, timeout=2)
            assert_feature_response(response, expected_frequency, expected_atoms)

    finally:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        stop_port_listener()
        PDB_PATH.write_bytes(original_pdb)
        WAV_PATH.write_bytes(original_wav)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
