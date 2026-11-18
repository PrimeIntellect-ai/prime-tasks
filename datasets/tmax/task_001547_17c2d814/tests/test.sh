#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust
export PATH="/opt/rust/bin:${PATH}"

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import json
import math
import os
import random
import signal
import subprocess
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

PROJECT = Path('/home/user/acoustic_pipeline')
WAV = Path('/app/sensor_stream.wav')
URL = 'http://127.0.0.1:8080/tensor'

assert (PROJECT / 'Cargo.toml').is_file(), 'Missing /home/user/acoustic_pipeline/Cargo.toml'
rust_sources = list((PROJECT / 'src').glob('**/*.rs'))
assert rust_sources, 'Cargo project contains no Rust source files under src/'
assert any(path.stat().st_size > 0 for path in rust_sources), 'Rust source files are empty'


def stop_port_8080():
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                socket_inodes.add(fields[9])

    victims = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    victims.add(int(proc.name))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def write_audio(frequencies, sample_rate=8000, secondary=None, phases=None):
    WAV.parent.mkdir(parents=True, exist_ok=True)
    if secondary is None:
        secondary = [None] * 6
    if phases is None:
        phases = [0.0] * 6
    assert len(frequencies) == len(secondary) == len(phases) == 6

    frames = bytearray()
    for index, frequency in enumerate(frequencies):
        second = secondary[index]
        phase = phases[index]
        for n in range(sample_rate):
            value = 0.72 * math.sin(2.0 * math.pi * frequency * n / sample_rate + phase)
            if second is not None:
                value += 0.18 * math.sin(2.0 * math.pi * second * n / sample_rate + phase / 2.0)
            sample = max(-32768, min(32767, int(round(value * 32767.0))))
            frames.extend(sample.to_bytes(2, byteorder='little', signed=True))

    with wave.open(str(WAV), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(frames)


def request_tensor():
    with urllib.request.urlopen(URL, timeout=5) as response:
        status = response.status
        body = response.read().decode('utf-8')
    assert status == 200, f'Expected status code 200, got {status}. Response: {body}'
    try:
        return json.loads(body)
    except ValueError as error:
        raise AssertionError(f'Failed to parse response as JSON. Response body: {body}') from error


def run_and_check(expected):
    stop_port_8080()
    process = subprocess.Popen(
        ['cargo', 'run', '--quiet'],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
        env=os.environ.copy(),
    )
    try:
        deadline = time.time() + 120
        last_error = None
        data = None
        while time.time() < deadline:
            if process.poll() is not None:
                stdout, stderr = process.communicate(timeout=2)
                raise AssertionError(
                    f'Rust application exited before serving /tensor.\nstdout:\n{stdout}\nstderr:\n{stderr}'
                )
            try:
                data = request_tensor()
                break
            except (urllib.error.URLError, TimeoutError, ConnectionError, AssertionError) as error:
                last_error = error
                time.sleep(0.25)
        else:
            raise AssertionError(f'Failed to connect to the Rust server at {URL}: {last_error}')

        assert data == expected, f'Expected JSON response {expected}, but got {data}'
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
        stop_port_8080()


# Preserve the original fixture and exact endpoint assertion, but execute the submitted Cargo project.
original = [400, 800, 500, 1200, 300, 900]
write_audio(original)
run_and_check([[400, 800, 500], [1200, 300, 900]])

# Exercise fresh, unpredictable WAV inputs so a constant endpoint cannot pass.
rng = random.SystemRandom()
for _ in range(2):
    categories = rng.sample(list(range(200, 1901, 100)), 6)
    frequencies = [category + rng.choice([-37, -29, -21, -13, 11, 19, 27, 34]) for category in categories]
    secondary = []
    for dominant in frequencies:
        options = [f for f in range(150, 1951, 50) if abs(f - dominant) >= 250]
        secondary.append(rng.choice(options))
    phases = [rng.random() * 2.0 * math.pi for _ in range(6)]
    write_audio(frequencies, secondary=secondary, phases=phases)
    expected = [categories[:3], categories[3:]]
    run_and_check(expected)
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
