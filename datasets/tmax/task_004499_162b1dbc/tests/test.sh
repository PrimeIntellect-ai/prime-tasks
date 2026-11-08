#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import subprocess
import tempfile
import time

import pytest
import requests

EVIL_DIR = '/app/corpora/evil'
CLEAN_DIR = '/app/corpora/clean'
FILTER_BIN = '/home/user/filter'
FILTER_SRC = '/home/user/filter.cpp'
URL = 'http://localhost:8080/submit'
PROBE_LOG = '/tmp/pde_probe.log'
PROBE_TOKEN = secrets.token_hex(16)


def get_corpus_files(directory):
    if not os.path.exists(directory):
        return []
    return [os.path.join(directory, f) for f in os.listdir(directory)
            if os.path.isfile(os.path.join(directory, f))]


def ode_is_evil(seq):
    n = len(seq)
    r = sum(c in 'GC' for c in seq) / n
    d = sum(c in 'AT' for c in seq) / n
    y = 0.1
    dt = 0.01
    for step in range(1000):
        t = step * dt
        y += dt * (r * y - d * y * y + __import__('math').sin(t))
        if y > 10.0:
            return True
    return False


def make_hidden_cases():
    rng = random.SystemRandom()
    cases = []
    # Deliberately cover many GC ratios, lengths, and orderings. Cases close to
    # the decision boundary are omitted to avoid dependence on insignificant
    # floating-point differences between Python and C++.
    for length in (37, 61, 89, 127):
        for pct in (0, 10, 25, 40, 50, 60, 70, 80, 85, 90, 95, 100):
            gc = round(length * pct / 100)
            chars = [rng.choice('GC') for _ in range(gc)]
            chars += [rng.choice('AT') for _ in range(length - gc)]
            rng.shuffle(chars)
            seq = ''.join(chars)
            # Compare 1000 and 1001 Euler updates and retain only cases on which
            # the endpoint convention cannot change the expected classification.
            expected = ode_is_evil(seq)
            y = 0.1
            r = gc / length
            d = (length - gc) / length
            import math
            for step in range(1001):
                y += 0.01 * (r * y - d * y * y + math.sin(step * 0.01))
                if y > 10.0:
                    break
            expected_1001 = y > 10.0
            if expected == expected_1001:
                cases.append((seq, expected))
    assert any(expected for _, expected in cases)
    assert any(not expected for _, expected in cases)
    return cases


HIDDEN_CASES = make_hidden_cases()


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f'Port {port} did not become ready')


@pytest.fixture(scope='session', autouse=True)
def controlled_services():
    # Use an unpredictable PDE response so a clean request can pass only by
    # actually reaching and returning the response of the backend.
    subprocess.run(['pkill', '-f', '/app/flask_app.py'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-f', '/app/pde_backend.py'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-9', 'nginx'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    with open(PROBE_LOG, 'w'):
        pass
    with open('/tmp/pde_probe.py', 'w') as f:
        f.write('''from flask import Flask, request\n'
app = Flask(__name__)\n'
TOKEN = %r\n'
LOG = %r\n'
@app.route("/simulate", methods=["POST"])\n'
def simulate():\n'
    seq = request.get_data(as_text=True)\n'
    with open(LOG, "a") as out:\n'
        out.write(seq + "\\n")\n'
    return TOKEN + ":" + seq, 200\n'
if __name__ == "__main__":\n'
    app.run(host="127.0.0.1", port=5001)\n''' % (PROBE_TOKEN, PROBE_LOG))

    devnull = open('/tmp/verifier_services.log', 'ab', buffering=0)
    env = os.environ.copy()
    probe = subprocess.Popen(['python3', '/tmp/pde_probe.py'], stdout=devnull, stderr=devnull, env=env)
    flask = subprocess.Popen(['python3', '/app/flask_app.py'], stdout=devnull, stderr=devnull, env=env)
    nginx = subprocess.run(['nginx', '-c', '/app/nginx.conf'], stdout=devnull, stderr=devnull)
    assert nginx.returncode == 0, 'Failed to start nginx with /app/nginx.conf'

    try:
        wait_for_port(5001)
        wait_for_port(5000)
        wait_for_port(8080)
        yield
    finally:
        flask.terminate()
        probe.terminate()
        subprocess.run(['pkill', '-9', 'nginx'], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for proc in (flask, probe):
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        devnull.close()


def clear_probe_log():
    with open(PROBE_LOG, 'w'):
        pass


def probe_lines():
    with open(PROBE_LOG, 'r') as f:
        return [line.rstrip('\n') for line in f]


def run_filter_sequence(seq):
    fd, path = tempfile.mkstemp(prefix='hidden_dna_', suffix='.txt')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(seq + '\n')
        return subprocess.run([FILTER_BIN, path], capture_output=True, timeout=5).returncode
    finally:
        os.unlink(path)


def test_filter_binary_exists():
    assert os.path.exists(FILTER_BIN), f'Filter binary {FILTER_BIN} does not exist.'
    assert os.access(FILTER_BIN, os.X_OK), f'Filter binary {FILTER_BIN} is not executable.'
    assert os.path.isfile(FILTER_SRC), f'C++ source {FILTER_SRC} does not exist.'
    assert os.path.isfile(FILTER_BIN), f'{FILTER_BIN} is not a regular file.'
    with open(FILTER_BIN, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Filter is not a compiled ELF executable.'


def test_filter_binary_evil_corpus():
    evil_files = get_corpus_files(EVIL_DIR)
    assert evil_files, f'No files found in {EVIL_DIR}'
    bypassed = []
    for filepath in evil_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True, timeout=5)
        if result.returncode != 1:
            bypassed.append(os.path.basename(filepath))
    if bypassed:
        pytest.fail(f'{len(bypassed)} of {len(evil_files)} evil bypassed: {", ".join(bypassed)}')


def test_filter_binary_clean_corpus():
    clean_files = get_corpus_files(CLEAN_DIR)
    assert clean_files, f'No files found in {CLEAN_DIR}'
    modified = []
    for filepath in clean_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True, timeout=5)
        if result.returncode != 0:
            modified.append(os.path.basename(filepath))
    if modified:
        pytest.fail(f'{len(modified)} of {len(clean_files)} clean modified (rejected): {", ".join(modified)}')


def test_filter_hidden_derived_sequences():
    failures = []
    for seq, evil in HIDDEN_CASES:
        expected_code = 1 if evil else 0
        actual = run_filter_sequence(seq)
        if actual != expected_code:
            failures.append((len(seq), seq.count('G') + seq.count('C'), expected_code, actual))
    assert not failures, f'Filter disagreed with derived Euler results: {failures[:8]}'


def test_end_to_end_evil_corpus():
    evil_files = get_corpus_files(EVIL_DIR)
    assert evil_files, f'No files found in {EVIL_DIR}'
    bypassed = []
    for filepath in evil_files:
        with open(filepath, 'r') as f:
            seq = f.read().strip()
        clear_probe_log()
        try:
            response = requests.post(URL, data=seq, timeout=5)
            if response.status_code != 400 or response.text != 'Unstable sequence rejected':
                bypassed.append(os.path.basename(filepath))
            assert seq not in probe_lines(), f'Evil sequence {filepath} reached the PDE backend'
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Service unreachable or crashed on {filepath}: {e}')
    if bypassed:
        pytest.fail(f'{len(bypassed)} of {len(evil_files)} evil bypassed via HTTP: {", ".join(bypassed)}')


def test_end_to_end_clean_corpus():
    clean_files = get_corpus_files(CLEAN_DIR)
    assert clean_files, f'No files found in {CLEAN_DIR}'
    modified = []
    for filepath in clean_files:
        with open(filepath, 'r') as f:
            seq = f.read().strip()
        clear_probe_log()
        try:
            response = requests.post(URL, data=seq, timeout=5)
            if response.status_code != 200:
                modified.append(os.path.basename(filepath))
            assert response.text == PROBE_TOKEN + ':' + seq, 'Clean response was not returned by the PDE backend'
            assert seq in probe_lines(), f'Clean sequence {filepath} was not forwarded to the PDE backend'
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Service unreachable or crashed on {filepath}: {e}')
    if modified:
        pytest.fail(f'{len(modified)} of {len(clean_files)} clean modified (rejected) via HTTP: {", ".join(modified)}')


def test_end_to_end_hidden_derived_sequences():
    evil_cases = [seq for seq, evil in HIDDEN_CASES if evil][:8]
    clean_cases = [seq for seq, evil in HIDDEN_CASES if not evil][:8]
    assert evil_cases and clean_cases

    for seq in evil_cases:
        clear_probe_log()
        response = requests.post(URL, data=seq, timeout=5)
        assert response.status_code == 400
        assert response.text == 'Unstable sequence rejected'
        assert seq not in probe_lines(), 'A hidden evil sequence reached the PDE backend'

    for seq in clean_cases:
        clear_probe_log()
        response = requests.post(URL, data=seq, timeout=5)
        assert response.status_code == 200
        assert response.text == PROBE_TOKEN + ':' + seq
        assert seq in probe_lines(), 'A hidden clean sequence was not forwarded to the PDE backend'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
