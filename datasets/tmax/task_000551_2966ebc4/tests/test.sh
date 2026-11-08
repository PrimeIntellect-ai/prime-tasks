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
import json
import math
import time
import signal
import socket
import secrets
import subprocess
from pathlib import Path

import requests
import numpy as np
import scipy.io.wavfile as wavfile

PROJECT = Path('/home/user/acoustic_service')
MANIFEST = PROJECT / 'Cargo.toml'


def kahan_sum(values):
    s = 0.0
    c = 0.0
    for v in values:
        y = v - c
        t = s + y
        c = (t - s) - y
        s = t
    return s


def compute_energy(segment_index, total_segments, start_freq, end_freq):
    sample_rate, data = wavfile.read('/app/stress_test.wav')
    data = data.astype(np.float64)
    segment_length = int(math.floor(len(data) / total_segments))
    start = segment_index * segment_length
    segment = data[start:start + segment_length]

    n = np.arange(segment_length)
    window = 0.5 * (1.0 - np.cos(2.0 * np.pi * n / (segment_length - 1)))
    fft_res = np.fft.fft(segment * window)
    energy = np.real(fft_res) ** 2 + np.imag(fft_res) ** 2
    freqs = np.arange(segment_length) * sample_rate / segment_length
    selected = energy[(freqs >= start_freq) & (freqs <= end_freq)]
    return kahan_sum(selected)


def compute_expected_energy():
    return compute_energy(1, 4, 1000.0, 2000.0)


def rust_project_and_binary():
    assert PROJECT.is_dir(), f'Rust project not found at {PROJECT}'
    assert MANIFEST.is_file(), f'Cargo.toml not found at {MANIFEST}'

    manifest_text = MANIFEST.read_text(errors='replace').lower()
    assert 'rustfft' in manifest_text, 'Cargo.toml must declare the rustfft dependency'

    sources = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert sources, 'No Rust source files were found in the project'
    source_text = '\n'.join(p.read_text(errors='replace') for p in sources).lower()
    assert 'rustfft' in source_text, 'Rust source does not use rustfft'
    assert 'kahan' in source_text, 'Rust source does not identify its required Kahan summation implementation'

    subprocess.run(
        ['cargo', 'build', '--offline', '--manifest-path', str(MANIFEST)],
        cwd=str(PROJECT), check=True, timeout=240,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    metadata = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
         '--manifest-path', str(MANIFEST)],
        cwd=str(PROJECT), check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    info = json.loads(metadata.stdout)
    manifest_real = str(MANIFEST.resolve())
    packages = [p for p in info['packages'] if str(Path(p['manifest_path']).resolve()) == manifest_real]
    assert packages, 'Cargo metadata did not contain the requested project'
    bins = [t['name'] for t in packages[0]['targets'] if 'bin' in t.get('kind', [])]
    assert bins, 'The Rust project has no executable binary target'
    binary = Path(info['target_directory']) / 'debug' / bins[0]
    assert binary.is_file() and os.access(binary, os.X_OK), f'Built Rust executable not found at {binary}'
    return binary


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                inodes.add(fields[9])

    result = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue
    return result


def launch_built_service(binary):
    for pid in listener_pids(8080):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 5
    while listener_pids(8080) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    log = open('/tmp/acoustic_service_verifier.log', 'ab', buffering=0)
    proc = subprocess.Popen(
        [str(binary)], cwd=str(PROJECT), stdout=log, stderr=log,
        start_new_session=True
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f'Built Rust service exited with status {proc.returncode}')
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.25):
                return proc
        except OSError:
            time.sleep(0.1)
    raise AssertionError('Built Rust service did not listen on 127.0.0.1:8080')


BUILT_BINARY = rust_project_and_binary()
SERVICE_PROCESS = launch_built_service(BUILT_BINARY)


def test_service_ready_file():
    ready_file = "/home/user/service_ready.txt"
    assert os.path.isfile(ready_file), f"Service ready file not found at {ready_file}"
    with open(ready_file, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"Expected ready file to contain 'READY', got '{content}'"


def post_and_validate(payload, expected_energy, rel_tol=1e-4):
    url = 'http://127.0.0.1:8080/analyze'
    try:
        resp = requests.post(url, json=payload, timeout=8)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f'Failed to connect to the service at {url}: {e}')

    assert resp.status_code == 200, f'Expected status code 200, got {resp.status_code}. Response: {resp.text}'
    try:
        data = resp.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError, ValueError):
        raise AssertionError(f'Failed to parse response as JSON. Response: {resp.text}')

    assert 'energy' in data, f"Response JSON missing 'energy' field: {data}"
    assert 'difference' in data, f"Response JSON missing 'difference' field: {data}"
    actual_energy = float(data['energy'])
    actual_difference = float(data['difference'])
    assert math.isfinite(actual_energy), f'Energy is not finite: {actual_energy}'
    assert math.isfinite(actual_difference), f'Difference is not finite: {actual_difference}'

    expected_difference = abs(expected_energy - float(payload['reference_val']))
    energy_tol = rel_tol * max(abs(expected_energy), 1.0)
    difference_tol = rel_tol * max(abs(expected_difference), abs(expected_energy), 1.0)
    assert abs(actual_energy - expected_energy) <= energy_tol, \
        f'Energy mismatch for {payload}. Expected ~{expected_energy}, got {actual_energy}'
    assert abs(actual_difference - expected_difference) <= difference_tol, \
        f'Difference mismatch for {payload}. Expected ~{expected_difference}, got {actual_difference}'
    return actual_energy


def test_analyze_endpoint():
    time.sleep(1)
    payload = {
        "segment_index": 1,
        "total_segments": 4,
        "start_freq": 1000.0,
        "end_freq": 2000.0,
        "reference_val": 50000000000.0
    }
    expected_energy = compute_expected_energy()
    post_and_validate(payload, expected_energy, rel_tol=1e-4)


def test_varied_domain_decomposition_bands_and_references():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(9):
        total_segments = rng.randint(2, 12)
        segment_index = rng.randrange(total_segments)
        start_freq = rng.uniform(20.0, 41000.0)
        width = rng.uniform(80.0, 5000.0)
        end_freq = min(44050.0, start_freq + width)
        expected = compute_energy(segment_index, total_segments, start_freq, end_freq)
        reference = rng.uniform(-0.75, 1.75) * max(expected, 1.0)
        cases.append((segment_index, total_segments, start_freq, end_freq, reference, expected))

    for segment_index, total_segments, start_freq, end_freq, reference, expected in cases:
        payload = {
            'segment_index': segment_index,
            'total_segments': total_segments,
            'start_freq': start_freq,
            'end_freq': end_freq,
            'reference_val': reference,
        }
        first_energy = post_and_validate(payload, expected, rel_tol=2e-7)

        second = dict(payload)
        second['reference_val'] = reference + rng.uniform(0.15, 0.85) * max(expected, 1.0)
        second_energy = post_and_validate(second, expected, rel_tol=2e-7)
        assert abs(first_energy - second_energy) <= 2e-7 * max(abs(expected), 1.0), \
            'Energy changed when only reference_val changed'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
