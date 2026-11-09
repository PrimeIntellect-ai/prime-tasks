#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import socket
import statistics
import pytest

HOST = '127.0.0.1'
PORT = 9000
DATASET = '/home/user/sensor_data.csv'
RESPONSE_RE = re.compile(r"^CI: -?\d+\.\d{4}, -?\d+\.\d{4}\n$")


def request_eval(n):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(f'EVAL {n}\n'.encode())
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if sum(map(len, chunks)) > 4096:
                pytest.fail('Service returned an excessively large response')
    except Exception as e:
        pytest.fail(f'Error communicating with service: {e}')
    finally:
        s.close()

    data = b''.join(chunks).decode('utf-8')
    if not RESPONSE_RE.match(data):
        pytest.fail(f'Invalid response format: {data!r}')
    parts = data.strip().split()
    lower, upper = [float(x.strip(',')) for x in parts[1:]]
    if lower >= upper:
        pytest.fail(f'Lower bound ({lower}) must be strictly less than upper bound ({upper})')
    return lower, upper


def listener_pids():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].endswith(':2328') and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass

    found = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    found.append(int(entry))
                    break
        except OSError:
            continue
    return found


def test_service_is_running_as_native_artifact():
    pids = listener_pids()
    if not pids:
        pytest.fail('No process is listening on TCP port 9000')

    native = False
    for pid in pids:
        try:
            with open(f'/proc/{pid}/exe', 'rb') as f:
                is_elf = f.read(4) == b'\x7fELF'
            with open(f'/proc/{pid}/maps', errors='ignore') as f:
                maps = f.read().lower()
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().lower()
        except OSError:
            continue
        interpreted = (b'python' in cmdline or b'node' in cmdline or
                       'libpython' in maps or 'libnode' in maps)
        if is_elf and not interpreted:
            native = True
            break
    if not native:
        pytest.fail('The listener is not running as a native compiled service')


def test_service_eval_700():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(('127.0.0.1', 9000))
    except Exception as e:
        pytest.fail(f"Could not connect to service on 127.0.0.1:9000: {e}")

    try:
        s.sendall(b'EVAL 700\n')
        data = s.recv(1024).decode('utf-8')
    except Exception as e:
        pytest.fail(f"Error communicating with service: {e}")
    finally:
        s.close()

    if not re.match(r"^CI: -?\d+\.\d{4}, -?\d+\.\d{4}\n$", data):
        pytest.fail(f"Invalid response format: {repr(data)}")

    parts = data.strip().split()
    lower, upper = [float(x.strip(',')) for x in parts[1:]]

    if not (-0.5 < lower < 0.1):
        pytest.fail(f"Lower bound {lower} out of expected range (-0.5, 0.1)")
    if not (-0.1 < upper < 0.5):
        pytest.fail(f"Upper bound {upper} out of expected range (-0.1, 0.5)")
    if lower >= upper:
        pytest.fail(f"Lower bound ({lower}) must be strictly less than upper bound ({upper})")


def test_service_eval_500():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(('127.0.0.1', 9000))
    except Exception as e:
        pytest.fail(f"Could not connect to service on 127.0.0.1:9000: {e}")

    try:
        s.sendall(b'EVAL 500\n')
        data = s.recv(1024).decode('utf-8')
    except Exception as e:
        pytest.fail(f"Error communicating with service: {e}")
    finally:
        s.close()

    if not re.match(r"^CI: -?\d+\.\d{4}, -?\d+\.\d{4}\n$", data):
        pytest.fail(f"Invalid response format: {repr(data)}")

    parts = data.strip().split()
    lower, upper = [float(x.strip(',')) for x in parts[1:]]

    if not (-0.5 < lower < 0.2):
        pytest.fail(f"Lower bound {lower} out of expected range for EVAL 500")
    if not (-0.2 < upper < 0.5):
        pytest.fail(f"Upper bound {upper} out of expected range for EVAL 500")
    if lower >= upper:
        pytest.fail(f"Lower bound ({lower}) must be strictly less than upper bound ({upper})")


def bootstrap_reference(values, n, seed):
    train = values[:n]
    test = values[n:]
    mean = statistics.fmean(train)
    std = statistics.stdev(train)
    scaled = [(x - mean) / std for x in test]

    rng = random.Random(seed)
    count = 16000
    size = len(scaled)
    means = []
    for _ in range(count):
        means.append(sum(scaled[rng.randrange(size)] for _ in range(size)) / size)
    means.sort()
    return means[int(0.025 * count)], means[int(0.975 * count)]


def test_randomized_dataset_and_split_indices():
    original = DATASET + '.verifier-backup'
    challenge = DATASET + '.verifier-challenge'
    seed = secrets.randbits(64)
    rng = random.Random(seed)

    slope = rng.uniform(0.020, 0.034)
    phase = rng.uniform(0.0, 2.0 * math.pi)
    jump1 = rng.uniform(0.8, 1.4)
    jump2 = rng.uniform(-0.7, -0.3)
    values = []
    for i in range(257):
        value = 5.0 + slope * i + 0.55 * math.sin(i / 9.0 + phase)
        value += rng.gauss(0.0, 0.22)
        if i >= 105:
            value += jump1
        if i >= 196:
            value += jump2
        values.append(value)

    splits = [rng.randint(72, 96), rng.randint(126, 151), rng.randint(178, 202)]
    expected = {n: bootstrap_reference(values, n, seed ^ (n << 17)) for n in splits}

    if os.path.exists(original):
        os.unlink(original)
    with open(challenge, 'w') as f:
        for value in values:
            f.write(f'{value:.12f}\n')
    os.chmod(challenge, 0o644)

    os.replace(DATASET, original)
    os.replace(challenge, DATASET)
    try:
        for n in splits:
            actual_lower, actual_upper = request_eval(n)
            expected_lower, expected_upper = expected[n]
            tolerance = 0.10
            if abs(actual_lower - expected_lower) > tolerance:
                pytest.fail(
                    f'EVAL {n} lower CI {actual_lower} differs from data-derived '
                    f'bootstrap value {expected_lower:.4f}'
                )
            if abs(actual_upper - expected_upper) > tolerance:
                pytest.fail(
                    f'EVAL {n} upper CI {actual_upper} differs from data-derived '
                    f'bootstrap value {expected_upper:.4f}'
                )
    finally:
        if os.path.exists(DATASET):
            os.unlink(DATASET)
        os.replace(original, DATASET)
        if os.path.exists(challenge):
            os.unlink(challenge)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
