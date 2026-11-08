#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import random
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import psutil
import pytest

REPO = Path('/home/user/poly_service')
SERVER = REPO / 'server.py'
SOCK_PATH = '/tmp/poly.sock'
SOLVER = Path('/app/poly_solver')
THRESHOLD_MB = 50.0


def _stop_server(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass


def _start_server():
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass
    proc = subprocess.Popen(
        ['python', str(SERVER)],
        cwd=str(REPO),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail('The server process terminated unexpectedly. Check if it binds to /tmp/poly.sock successfully.')
        if os.path.exists(SOCK_PATH):
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                probe.settimeout(0.5)
                probe.connect(SOCK_PATH)
                probe.close()
                return proc
            except OSError:
                probe.close()
        time.sleep(0.05)
    _stop_server(proc)
    pytest.fail(f'Socket {SOCK_PATH} does not exist or cannot be connected to.')


def _query(payload):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        client.connect(SOCK_PATH)
        client.sendall(payload)
        client.shutdown(socket.SHUT_WR)
        response = bytearray()
        while b'\n' not in response:
            chunk = client.recv(1024)
            if not chunk:
                break
            response.extend(chunk)
        return bytes(response)
    finally:
        client.close()


def _vmhwm_mb(pid):
    try:
        with open(f'/proc/{pid}/status') as f:
            for line in f:
                if line.startswith('VmHWM:'):
                    return int(line.split()[1]) / 1024.0
    except (FileNotFoundError, ProcessLookupError):
        pass
    return 0.0


def test_poly_solver_executable():
    solver_path = str(SOLVER)
    assert os.path.isfile(solver_path), f'Expected file {solver_path} does not exist.'
    assert os.access(solver_path, os.X_OK), f'File {solver_path} is not executable. The environment issue was not fixed.'


def test_fuzzing_and_bisection_evidence():
    candidates = []
    for path in REPO.rglob('*'):
        if not path.is_file() or '.git' in path.parts or path == SERVER or path.stat().st_size > 1_000_000:
            continue
        if 'fuzz' not in path.name.lower():
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        numbers = [int(x) for x in re.findall(r'\b\d+\b', text)]
        if (('/tmp/poly.sock' in text or 'AF_UNIX' in text)
                and ('sendall' in text or '.send(' in text)
                and 'random' in text.lower()
                and any(n >= 1000 for n in numbers)):
            candidates.append(path)
    assert candidates, 'No fuzzing script that sends thousands of randomized Unix-socket requests was found.'

    intro = subprocess.check_output(
        ['git', '-C', str(REPO), 'log', '--all', '--reverse',
         '-S', 'audit_log.append(data.decode() * 1000)', '--format=%H', '--', 'server.py'],
        text=True,
    ).splitlines()
    assert intro, 'Could not locate the leak-introducing commit in repository history.'
    bad_commit = intro[0]

    reflog = subprocess.check_output(
        ['git', '-C', str(REPO), 'reflog', 'show', 'HEAD', '--format=%H%x09%gs'],
        text=True,
    ).splitlines()
    checkout_rows = [line for line in reflog if '\tcheckout: moving from ' in line]
    checkout_hashes = {line.split('\t', 1)[0] for line in checkout_rows}
    assert bad_commit in checkout_hashes, 'Git reflog does not show the first bad commit being checked out during bisection.'
    assert len(checkout_hashes) >= 3, 'Git reflog does not show enough historical revisions being tested for a real bisection.'


def test_server_invokes_binary_and_relays_its_output():
    real_solver = Path(f'/tmp/poly_solver.real.{os.getpid()}')
    log_path = Path(f'/tmp/poly_solver.calls.{os.getpid()}')
    secret = os.urandom(32).hex()
    os.replace(SOLVER, real_solver)
    wrapper = f'''#!/usr/bin/env python3
import base64, hashlib, sys
payload = sys.stdin.buffer.read()
with open({str(log_path)!r}, 'ab') as f:
    f.write(base64.b64encode(payload) + b"\\n")
out = "SPY:" + hashlib.sha256(bytes.fromhex({secret!r}) + payload).hexdigest() + "\\n"
sys.stdout.write(out)
sys.stdout.flush()
'''
    SOLVER.write_text(wrapper)
    os.chmod(SOLVER, 0o755)

    proc = None
    payloads = []
    try:
        proc = _start_server()
        rng = random.Random(918273)
        for _ in range(12):
            payload = (' '.join(f'{rng.uniform(-10, 10):.12g}' for _ in range(5)) + '\n').encode()
            payloads.append(payload)
            expected = ('SPY:' + hashlib.sha256(bytes.fromhex(secret) + payload).hexdigest() + '\n').encode()
            response = _query(payload)
            assert response, 'The service returned an empty response.'
            assert response == expected, f'The service did not relay /app/poly_solver output: {response!r}'
        calls = [base64.b64decode(line) for line in log_path.read_bytes().splitlines()]
        assert calls == payloads, 'The service did not invoke /app/poly_solver once with each request payload.'
    finally:
        if proc is not None:
            _stop_server(proc)
        try:
            SOLVER.unlink()
        except FileNotFoundError:
            pass
        os.replace(real_solver, SOLVER)
        try:
            log_path.unlink()
        except FileNotFoundError:
            pass


def test_server_memory_leak_and_correct_results():
    assert SERVER.is_file(), f'Expected file {SERVER} does not exist.'

    rng = random.Random(246813579)
    requests = [
        (' '.join(f'{rng.uniform(-10, 10):.12g}' for _ in range(5)) + '\n').encode()
        for _ in range(10000)
    ]
    oracle_output = subprocess.check_output([str(SOLVER)], input=b''.join(requests))
    expected = oracle_output.splitlines(keepends=True)
    assert len(expected) == len(requests), 'The polynomial solver returned an unexpected number of reference results.'

    proc = _start_server()
    peak_samples = [0.0]
    sampling = threading.Event()

    def sample_rss():
        try:
            process = psutil.Process(proc.pid)
            while not sampling.is_set():
                peak_samples[0] = max(peak_samples[0], process.memory_info().rss / (1024 * 1024))
                time.sleep(0.002)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    sampler = threading.Thread(target=sample_rss, daemon=True)
    sampler.start()
    try:
        for i, (payload, wanted) in enumerate(zip(requests, expected)):
            response = _query(payload)
            assert response, f'The service returned an empty response for request {i}.'
            assert response == wanted, f'Incorrect polynomial result for request {i}: expected {wanted!r}, got {response!r}'
            assert proc.poll() is None, 'The server process terminated during the benchmark.'

        process = psutil.Process(proc.pid)
        final_rss_mb = process.memory_info().rss / (1024 * 1024)
        kernel_peak_mb = _vmhwm_mb(proc.pid)
        peak_rss_mb = max(peak_samples[0], kernel_peak_mb, final_rss_mb)
    finally:
        sampling.set()
        sampler.join(timeout=2)
        _stop_server(proc)

    assert final_rss_mb <= THRESHOLD_MB, f'Memory leak detected! Final RSS was {final_rss_mb:.2f} MB, greater than {THRESHOLD_MB} MB.'
    assert peak_rss_mb <= THRESHOLD_MB, f'Memory leak detected! Peak RSS was {peak_rss_mb:.2f} MB, greater than {THRESHOLD_MB} MB.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
