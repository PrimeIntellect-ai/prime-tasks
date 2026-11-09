#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the image's API so the worker can be exercised against verifier-controlled data.
pkill -f '/app/data_api.py' 2>/dev/null || true
sleep 1
redis-server --daemonize yes >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import pytest

WORKER_DIR = '/home/user/worker'
OUTPUT_PATH = '/home/user/final_kl.txt'


def gaussian_kl(mu0, cov0, mu1, cov1):
    # The task requires regularization before inverses and determinants.
    reg = np.eye(2) * 1e-4
    s0 = np.asarray(cov0, dtype=float) + reg
    s1 = np.asarray(cov1, dtype=float) + reg
    inv1 = np.linalg.inv(s1)
    delta = np.asarray(mu1, dtype=float) - np.asarray(mu0, dtype=float)
    value = 0.5 * (
        np.trace(inv1 @ s0)
        + delta.T @ inv1 @ delta
        - 2.0
        + math.log(np.linalg.det(s1) / np.linalg.det(s0))
    )
    return float(value)


def test_worker_and_final_kl_divergence():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    # Build a fresh near-singular test distribution. The fitted distribution is
    # deliberately close to, but not identical to, truth so a hard-coded zero
    # cannot satisfy the behavioral check.
    rng = random.SystemRandom()
    large_eig = rng.uniform(1.7, 2.2)
    small_eig = rng.uniform(0.0007, 0.0013)
    fitted_small_eig = small_eig * rng.uniform(1.15, 1.30)
    truth_mean = np.array([rng.uniform(-4.0, 7.0), rng.uniform(-5.0, 6.0)])
    shift = rng.uniform(0.10, 0.18) * rng.choice([-1.0, 1.0])

    major = np.array([1.0, 1.0]) / math.sqrt(2.0)
    minor = np.array([1.0, -1.0]) / math.sqrt(2.0)
    fitted_mean = truth_mean + shift * major
    truth_cov = large_eig * np.outer(major, major) + small_eig * np.outer(minor, minor)
    fitted_cov = large_eig * np.outer(major, major) + fitted_small_eig * np.outer(minor, minor)

    # These 100 deterministic points have exactly fitted_mean and fitted_cov
    # when population covariance (division by N) is used.
    points = []
    for k in range(100):
        angle = 2.0 * math.pi * k / 100.0
        z0 = math.sqrt(2.0) * math.cos(angle)
        z1 = math.sqrt(2.0) * math.sin(angle)
        point = (fitted_mean
                 + math.sqrt(large_eig) * z0 * major
                 + math.sqrt(fitted_small_eig) * z1 * minor)
        points.append(point.tolist())

    state = {'requests': []}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state['requests'].append(self.path)
            if self.path == '/data':
                # Correct convergence on identical batches should occur quickly;
                # this prevents a fixed long iteration loop from masquerading as
                # the required KL convergence test.
                if state['requests'].count('/data') > 10:
                    self.send_response(429)
                    self.end_headers()
                    return
                body = json.dumps(points).encode()
            elif self.path == '/truth':
                body = json.dumps({
                    'mean': truth_mean.tolist(),
                    'cov': truth_cov.tolist(),
                }).encode()
            else:
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    try:
        server = ThreadingHTTPServer(('127.0.0.1', 8000), Handler)
    except OSError as exc:
        pytest.fail(f'Could not start verifier-controlled Data API: {exc}')
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        # Retain the requested Makefile build, then independently compile the
        # demanded C++ source into the executable that is actually exercised.
        built = subprocess.run(
            ['make', 'clean', 'all'], cwd=WORKER_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=60
        )
        assert built.returncode == 0, 'Makefile build failed:\n' + built.stdout[-4000:]

        compiled = subprocess.run(
            ['g++', '-std=c++11', '-O2', '-o', 'estimator', 'estimator.cpp', '-lpthread'],
            cwd=WORKER_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=60
        )
        assert compiled.returncode == 0, 'Direct estimator.cpp build failed:\n' + compiled.stdout[-4000:]

        executable = os.path.join(WORKER_DIR, 'estimator')
        assert os.path.isfile(executable), 'Compiled estimator executable is missing'
        with open(executable, 'rb') as f:
            assert f.read(4) == b'\x7fELF', 'estimator is not a compiled ELF executable'

        run = subprocess.run(
            [executable], cwd=WORKER_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=30
        )
        assert run.returncode == 0, 'Worker execution failed:\n' + run.stdout[-4000:]
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f'Build or worker timed out: {exc}')
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    data_count = state['requests'].count('/data')
    truth_count = state['requests'].count('/truth')
    assert 2 <= data_count <= 10, (
        f'Worker made {data_count} /data requests; it did not demonstrate convergence '
        'between successive estimates'
    )
    assert truth_count >= 1, 'Worker did not fetch ground truth from /truth'
    first_truth = state['requests'].index('/truth')
    assert state['requests'][:first_truth].count('/data') >= 2, (
        'Worker fetched /truth before performing the convergence iterations'
    )

    # Preserve the original output assertions.
    assert os.path.isfile(OUTPUT_PATH), f'Output file missing: {OUTPUT_PATH}'
    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float in {OUTPUT_PATH}")
    assert 0.0 <= val < 0.05, f'KL divergence {val} is outside acceptable bounds [0.0, 0.05)'

    # Accept the two conventional covariance normalizations (N and N-1), but
    # independently derive the required regularized KL in both cases.
    expected_population = gaussian_kl(fitted_mean, fitted_cov, truth_mean, truth_cov)
    expected_sample = gaussian_kl(
        fitted_mean, fitted_cov * (100.0 / 99.0), truth_mean, truth_cov
    )
    assert min(abs(val - expected_population), abs(val - expected_sample)) < 3e-4, (
        f'Reported KL {val} does not match the worker input and API truth; '
        f'expected approximately {expected_population} (N) or {expected_sample} (N-1)'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
