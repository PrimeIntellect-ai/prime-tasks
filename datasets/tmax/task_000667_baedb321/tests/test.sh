#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import string
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import redis

CLEAN_CORPUS_DIR = Path('/app/corpora/clean')
EVIL_CORPUS_DIR = Path('/app/corpora/evil')
RUST_PROJECT_DIR = Path('/home/user/sequence_filter')
START_SCRIPT = Path('/app/start_services.sh')


def port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex(('127.0.0.1', port)) == 0


def wait_port(port, wanted=True, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_open(port) == wanted:
            return
        time.sleep(0.1)
    raise AssertionError(f'Port {port} did not become {"available" if wanted else "closed"}')


def stop_services():
    try:
        redis.Redis(host='127.0.0.1', port=6379, socket_timeout=1).shutdown(nosave=True)
    except Exception:
        pass
    for pattern in ('provider.py', 'aggregator.js', 'redis-server'):
        subprocess.run(['pkill', '-f', pattern], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    for port in (6379, 5000, 3000):
        try:
            wait_port(port, False, 5)
        except AssertionError:
            pass


def provider_has_redis_env():
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            environ = (proc / 'environ').read_bytes().split(b'\0')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if 'provider.py' in cmdline and b'REDIS_HOST=127.0.0.1' in environ:
            return True
    return False


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    baseline_requests = 0
    flags = []
    lock = threading.Lock()

    def do_GET(self):
        if self.server.server_port == 5000 and self.path == '/baseline_score':
            with Handler.lock:
                Handler.baseline_requests += 1
            body = b'4.25'
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.server.server_port != 3000 or self.path != '/flag':
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode('utf-8'))
        except Exception:
            self.send_error(400)
            return
        if not isinstance(payload, dict) or not isinstance(payload.get('filename'), str):
            self.send_error(400)
            return
        with Handler.lock:
            Handler.flags.append(payload['filename'])
        self.send_response(200)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def reset_observations():
    with Handler.lock:
        Handler.baseline_requests = 0
        Handler.flags = []


def observations():
    with Handler.lock:
        return Handler.baseline_requests, list(Handler.flags)


def redis_read_calls(client):
    info = client.info('commandstats')
    return sum(info.get(name, {}).get('calls', 0) for name in
               ('cmdstat_get', 'cmdstat_mget'))


def run_filter(input_dir, output_dir, redis_client, timeout=180):
    before = redis_read_calls(redis_client)
    result = subprocess.run(
        ['cargo', 'run', '--release', '--', str(input_dir), str(output_dir)],
        cwd=RUST_PROJECT_DIR, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f'Cargo run failed for {input_dir}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}')
    after = redis_read_calls(redis_client)
    assert after > before, 'The classifier did not fetch data from Redis during execution'


def fasta_files(path):
    return {p.name: p for p in Path(path).iterdir() if p.suffix == '.fasta'}


def assert_exact_outputs(input_dir, output_dir, expected_names):
    inputs = fasta_files(input_dir)
    outputs = fasta_files(output_dir)
    assert set(outputs) == set(expected_names), (
        f'Expected output files {sorted(expected_names)}, got {sorted(outputs)}')
    for name in expected_names:
        assert outputs[name].read_bytes() == inputs[name].read_bytes(), (
            f'Output {name} is not an exact copy of the original FASTA file')


def test_complete_pipeline():
    # Preserve and strengthen the original service/startup assertions.
    assert START_SCRIPT.is_file(), '/app/start_services.sh is missing'
    assert os.access(START_SCRIPT, os.X_OK), '/app/start_services.sh is not executable'
    script_text = START_SCRIPT.read_text(errors='ignore')
    assert '6379' in script_text, 'Startup script does not configure Redis port 6379'
    assert 'REDIS_HOST' in script_text and '127.0.0.1' in script_text, (
        'Startup script does not provide REDIS_HOST=127.0.0.1 to the provider')

    stop_services()
    launcher = subprocess.Popen(
        ['bash', str(START_SCRIPT)], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        for port in (6379, 5000, 3000):
            wait_port(port, True, 20)

        r = redis.Redis(host='127.0.0.1', port=6379, socket_timeout=2)
        assert r.ping(), 'Redis on 127.0.0.1:6379 did not answer PING'
        bind_value = r.config_get('bind').get('bind', '')
        assert '127.0.0.1' in bind_value.split(), f'Redis bind setting is {bind_value!r}'
        assert provider_has_redis_env(), 'Provider was not started with REDIS_HOST=127.0.0.1'

        with urllib.request.urlopen('http://127.0.0.1:5000/baseline_score', timeout=3) as response:
            assert float(response.read().decode().strip()) == 4.25
        probe = urllib.request.Request(
            'http://127.0.0.1:3000/flag',
            data=json.dumps({'filename': 'verifier_probe.fasta'}).encode(),
            headers={'Content-Type': 'application/json'}, method='POST')
        with urllib.request.urlopen(probe, timeout=3) as response:
            assert response.status == 200
    finally:
        stop_services()
        try:
            os.killpg(launcher.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    # The demanded artifact must be a real Cargo/Rust project.
    assert (RUST_PROJECT_DIR / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    rust_sources = list((RUST_PROJECT_DIR / 'src').rglob('*.rs'))
    assert rust_sources, 'No Rust source files exist under sequence_filter/src'
    source = '\n'.join(p.read_text(errors='ignore') for p in rust_sources)
    assert 'substitution_weights' in source, 'Rust code does not reference substitution_weights'
    assert '127.0.0.1:5000' in source and 'baseline_score' in source, (
        'Rust code does not reference the baseline service')
    assert '127.0.0.1:3000' in source and '/flag' in source, (
        'Rust code does not reference the aggregator endpoint')
    assert ('1e-4' in source.lower() or '0.0001' in source), (
        'Rust code does not contain the required convergence threshold')

    # Supply the previously missing Redis data before executing the classifier.
    redis_proc = subprocess.Popen(
        ['redis-server', '--bind', '127.0.0.1', '--port', '6379',
         '--save', '', '--appendonly', 'no'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    provider_server = aggregator_server = None
    try:
        wait_port(6379, True, 10)
        r = redis.Redis(host='127.0.0.1', port=6379, socket_timeout=3)
        r.set('substitution_weights', json.dumps([1.0] * 64))

        provider_server = ReusableHTTPServer(('127.0.0.1', 5000), Handler)
        aggregator_server = ReusableHTTPServer(('127.0.0.1', 3000), Handler)
        threading.Thread(target=provider_server.serve_forever, daemon=True).start()
        threading.Thread(target=aggregator_server.serve_forever, daemon=True).start()
        wait_port(5000, True, 5)
        wait_port(3000, True, 5)

        # Keep the original known-corpus behavioral checks, while checking contents
        # and required service communication as well as filenames.
        reset_observations()
        with tempfile.TemporaryDirectory() as out:
            run_filter(CLEAN_CORPUS_DIR, out, r)
            clean_names = set(fasta_files(CLEAN_CORPUS_DIR))
            assert_exact_outputs(CLEAN_CORPUS_DIR, out, clean_names)
        baseline_count, flags = observations()
        assert baseline_count > 0, 'Clean-corpus run never requested the analytical baseline'
        assert not flags, f'Clean files were incorrectly reported as anomalous: {flags[:5]}'

        reset_observations()
        with tempfile.TemporaryDirectory() as out:
            run_filter(EVIL_CORPUS_DIR, out, r)
            assert_exact_outputs(EVIL_CORPUS_DIR, out, set())
        baseline_count, flags = observations()
        evil_names = set(fasta_files(EVIL_CORPUS_DIR))
        assert baseline_count > 0, 'Evil-corpus run never requested the analytical baseline'
        assert evil_names.issubset(set(flags)), (
            f'Not every rejected evil file was POSTed to the aggregator; missing '
            f'{sorted(evil_names - set(flags))[:5]}')

        # Exercise a single mixed, unpredictably named directory so classification
        # cannot be based on the fixed clean/evil path or filename prefixes.
        reset_observations()
        rng = random.SystemRandom()
        with tempfile.TemporaryDirectory(prefix='sequence-input-') as inp, \
             tempfile.TemporaryDirectory(prefix='sequence-output-') as out:
            inp = Path(inp)
            expected_clean = set()
            expected_evil = set()
            for index in range(12):
                name = uuid.uuid4().hex + '.fasta'
                header = ''.join(rng.choice(string.ascii_letters) for _ in range(18))
                sequence = ''.join(rng.choice('ACGT') for _ in range(100))
                (inp / name).write_text(f'>{header}\n{sequence}\n')
                expected_clean.add(name)
            for index in range(12):
                name = uuid.uuid4().hex + '.fasta'
                header = ''.join(rng.choice(string.ascii_letters) for _ in range(18))
                sequence = ('ACG' * 34)[:100]
                (inp / name).write_text(f'>{header}\n{sequence}\n')
                expected_evil.add(name)

            run_filter(inp, out, r)
            assert_exact_outputs(inp, out, expected_clean)
            baseline_count, flags = observations()
            assert baseline_count > 0, 'Mixed run never requested the analytical baseline'
            assert expected_evil.issubset(set(flags)), (
                f'Mixed-run rejected files were not all reported; missing '
                f'{sorted(expected_evil - set(flags))[:5]}')
            assert not (expected_clean & set(flags)), 'Accepted files were reported as evil'

        log_path = Path('/home/user/verification.log')
        assert log_path.is_file(), '/home/user/verification.log is missing'
        log = log_path.read_text(errors='ignore').lower()
        assert re.search(r'processed[^0-9]{0,20}24\b', log), (
            'verification.log does not report 24 processed files for the final run')
        assert re.search(r'accepted[^0-9]{0,20}12\b', log), (
            'verification.log does not report 12 accepted files for the final run')
        assert re.search(r'rejected[^0-9]{0,20}12\b', log), (
            'verification.log does not report 12 rejected files for the final run')
    finally:
        if provider_server:
            provider_server.shutdown()
            provider_server.server_close()
        if aggregator_server:
            aggregator_server.shutdown()
            aggregator_server.server_close()
        try:
            r.shutdown(nosave=True)
        except Exception:
            pass
        redis_proc.terminate()
        try:
            redis_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            redis_proc.kill()
PYTEST

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
