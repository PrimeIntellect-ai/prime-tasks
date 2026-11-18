#!/bin/bash
mkdir -p /logs/verifier

# Replace the permissive backend with an instrumented backend so forwarding and
# response propagation can be checked without trusting the submitted scripts.
python3 - <<'PY' || true
import os, signal, time
port_hex = format(8081, '04X')
inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(':')[-1].upper() == port_hex and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
time.sleep(1)
PY

cat > /tmp/verifier_backend.py <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib

COUNT = '/tmp/verifier_backend_count'

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        digest = hashlib.sha256(body).hexdigest()
        with open('/tmp/verifier_backend_last', 'wb') as f:
            f.write(body)
        with open(COUNT, 'a') as f:
            f.write(digest + '\n')
        response = ('BACKEND:' + digest).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
PY
: > /tmp/verifier_backend_count
python3 /tmp/verifier_backend.py >/tmp/verifier_backend.log 2>&1 &
BACKEND_PID=$!
sleep 1

cat > /tmp/test_final_state.py <<'PY'
import glob
import hashlib
import os
import re
import subprocess
import urllib.error
import urllib.request

import numpy as np

URL = 'http://127.0.0.1:8000/api/process'
GUARD = '/home/user/stability_guard.sh'
CGI = '/home/user/cgi_proxy.sh'
NGINX = '/home/user/nginx.conf'


def request(body, timeout=8):
    req = urllib.request.Request(URL, data=body, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def backend_count():
    try:
        with open('/tmp/verifier_backend_count') as f:
            return sum(1 for line in f if line.strip())
    except FileNotFoundError:
        return 0


def run_guard(body):
    return subprocess.run(
        [GUARD], input=body, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=8, check=False
    )


def encoded_signal(values):
    return ''.join(f'{x:.17g}\n' for x in values).encode()


def spectral_signal(rng, upper_powers, n=1000):
    """Create a real signal with controlled normalized rFFT-bin powers."""
    spectrum = np.zeros(n // 2 + 1, dtype=np.complex128)
    split = len(spectrum) // 2
    lower_powers = rng.uniform(0.4, 1.4, split - 1)
    lower_phases = rng.uniform(0, 2 * np.pi, split - 1)
    spectrum[1:split] = np.sqrt(lower_powers * n) * np.exp(1j * lower_phases)
    upper_powers = np.asarray(upper_powers, dtype=float)
    assert len(upper_powers) == len(spectrum) - split
    upper_phases = rng.uniform(0, 2 * np.pi, len(upper_powers))
    spectrum[split:] = np.sqrt(upper_powers * n) * np.exp(1j * upper_phases)
    spectrum[-1] = spectrum[-1].real
    return np.fft.irfft(spectrum, n=n)


def test_required_artifacts_and_configuration_exist():
    for path in (GUARD, CGI, NGINX):
        assert os.path.isfile(path), f'Missing required file: {path}'
        assert os.path.getsize(path) > 0, f'Required file is empty: {path}'
    assert os.access(GUARD, os.X_OK), 'stability_guard.sh is not executable'
    assert os.access(CGI, os.X_OK), 'cgi_proxy.sh is not executable'

    guard = open(GUARD, errors='replace').read()
    cgi = open(CGI, errors='replace').read()
    nginx = open(NGINX, errors='replace').read()
    assert re.search(r'^#!.*\bbash\b', guard, re.M), 'guard must be Bash-based'
    assert re.search(r'fft|rfft', guard, re.I), 'guard contains no FFT computation'
    assert re.search(r'bootstrap|resampl|random|choice|shuf', guard, re.I), 'guard contains no bootstrap/resampling logic'
    assert re.search(r'percentile|quantile|confidence|95|2\.5', guard, re.I), 'guard contains no 95% confidence-interval logic'
    assert re.search(r'15(?:\.0)?', guard), 'guard does not implement the required 15.0 threshold'
    assert re.search(r'cond|condition|ill.?condition', guard, re.I), 'guard contains no condition-number/instability logic'

    assert 'stability_guard.sh' in cgi, 'CGI wrapper does not invoke the guard'
    assert re.search(r'curl', cgi, re.I), 'CGI wrapper does not forward with curl'
    assert '127.0.0.1:8081/factorize' in cgi, 'CGI wrapper does not target the matrix service'
    assert re.search(r'listen\s+127\.0\.0\.1:8000|listen\s+8000', nginx), 'nginx does not listen on port 8000'
    assert '/api/process' in nginx, 'nginx lacks the required route'
    assert '/tmp/fcgiwrap.socket' in nginx, 'nginx is not configured for the fcgiwrap socket'
    assert re.search(r'fastcgi_pass|fastcgi_param', nginx), 'nginx lacks FastCGI configuration'


def test_evil_corpus_rejected():
    evil_files = glob.glob('/app/data/evil/*.txt')
    assert len(evil_files) == 50, f'Expected 50 evil files, found {len(evil_files)}'
    bypassed = []
    for filepath in evil_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        try:
            status, _ = request(data)
        except Exception as error:
            status = str(error)
        if status != 400:
            bypassed.append(os.path.basename(filepath))
    assert not bypassed, f'{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed[:10]}'


def test_clean_corpus_accepted():
    clean_files = glob.glob('/app/data/clean/*.txt')
    assert len(clean_files) == 50, f'Expected 50 clean files, found {len(clean_files)}'
    modified = []
    for filepath in clean_files:
        with open(filepath, 'rb') as f:
            data = f.read()
        try:
            status, _ = request(data)
        except Exception as error:
            status = str(error)
        if status != 200:
            modified.append(os.path.basename(filepath))
    assert not modified, f'{len(modified)} of {len(clean_files)} clean modified: {modified[:10]}'


def test_randomized_fft_and_bootstrap_cases_end_to_end():
    # These signals are generated only after the agent has finished. Uniformly
    # low upper-bin power is stable; uniformly high power has a 95% bootstrap
    # lower bound above 15. The mixed case has mean 15.5 but a lower confidence
    # bound below 15, detecting implementations that merely threshold the mean.
    rng = np.random.default_rng()
    cases = []
    bins = 1000 // 2 + 1 - (1000 // 2 + 1) // 2
    for _ in range(3):
        cases.append((spectral_signal(rng, rng.uniform(0.3, 2.0, bins)), True))
        cases.append((spectral_signal(rng, rng.uniform(25.0, 45.0, bins)), False))
    mixed = np.concatenate((np.full(bins // 2, 8.0), np.full(bins - bins // 2, 23.0)))
    rng.shuffle(mixed)
    cases.append((spectral_signal(rng, mixed), True))

    for signal, accepted in cases:
        body = encoded_signal(signal)
        direct = run_guard(body)
        expected_rc = 0 if accepted else 1
        assert direct.returncode == expected_rc, (
            f'guard returned {direct.returncode}, expected {expected_rc}; '
            f'stderr={direct.stderr[:300]!r}'
        )
        before = backend_count()
        status, response = request(body)
        if accepted:
            digest = hashlib.sha256(body).hexdigest().encode()
            assert status == 200, f'dynamic stable signal returned HTTP {status}'
            assert response == b'BACKEND:' + digest, 'backend response was not propagated unchanged'
            assert open('/tmp/verifier_backend_last', 'rb').read() == body, 'CGI did not forward the exact request body'
            assert backend_count() == before + 1, 'accepted request did not reach the backend exactly once'
        else:
            assert status == 400, f'dynamic unstable signal returned HTTP {status}'
            assert response.strip() == b'REJECTED', f'wrong rejection body: {response!r}'
            assert backend_count() == before, 'rejected request was incorrectly forwarded to the backend'


def test_extreme_low_frequency_condition_instability_is_rejected():
    rng = np.random.default_rng()
    # A massive DC offset with tiny variation is a near-rank-one/ill-conditioned
    # input, while its upper-frequency power alone is low.
    signal = 1.0e9 + rng.normal(0.0, 1.0e-4, 1000)
    body = encoded_signal(signal)
    direct = run_guard(body)
    assert direct.returncode == 1, f'guard accepted extreme-offset ill-conditioned input: {direct.stderr[:300]!r}'
    before = backend_count()
    status, response = request(body)
    assert status == 400, f'condition-unstable signal returned HTTP {status}'
    assert response.strip() == b'REJECTED'
    assert backend_count() == before, 'condition-unstable input reached the backend'
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

kill "$BACKEND_PID" 2>/dev/null || true
