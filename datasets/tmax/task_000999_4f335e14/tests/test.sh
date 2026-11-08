#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_organizer.py
import fcntl
import hashlib
import http.server
import json
import os
import pwd
import random
import re
import secrets
import shutil
import socketserver
import struct
import subprocess
import threading
import time
from pathlib import Path

SOURCE = Path('/home/user/organizer.cpp')
BINARY = Path('/home/user/organizer')
RAW = Path('/app/raw_data')
SUMMARY_DIR = Path('/app/organized_data')
USER = pwd.getpwnam('user')

rules = {'target_dir': '/app/organized_data', 'prefix': 'clean'}
rules_lock = threading.Lock()
request_count = 0

class RulesHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global request_count
        if self.path != '/rules':
            self.send_error(404)
            return
        with rules_lock:
            request_count += 1
            body = json.dumps(rules).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def as_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_worker(path, timeout=15):
    return subprocess.Popen(
        [str(path)], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, preexec_fn=as_user,
        env={'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
             'HOME': '/home/user'}
    )


def clear_dir(path):
    path.mkdir(parents=True, exist_ok=True)
    for entry in path.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()
    os.chmod(path, 0o777)


def write_payload(path, sensor_id, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o777)
    payload = struct.pack('<i100f', sensor_id, *values)
    path.write_bytes(payload)
    return payload


def redis_members():
    output = subprocess.check_output(
        ['redis-cli', '--raw', 'SMEMBERS', 'processed_sensors'], text=True
    )
    return {int(x) for x in output.splitlines() if x.strip()}


def read_summary(expected_means):
    summary = SUMMARY_DIR / 'summary.csv'
    assert summary.is_file(), 'summary.csv was not created'
    lines = summary.read_text().splitlines()
    assert len(lines) == len(expected_means), (
        f'summary.csv has {len(lines)} lines; expected {len(expected_means)}'
    )
    seen = set()
    pattern = re.compile(r'^(-?\d+),(-?\d+\.\d{4})$')
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f'invalid summary line: {line!r}'
        sensor_id = int(match.group(1))
        assert sensor_id in expected_means, f'unexpected sensor ID {sensor_id} in CSV'
        assert sensor_id not in seen, f'duplicate sensor ID {sensor_id} in CSV'
        seen.add(sensor_id)
        actual = float(match.group(2))
        assert abs(actual - expected_means[sensor_id]) <= 0.00015, (
            f'incorrect mean for sensor {sensor_id}: {actual} versus {expected_means[sensor_id]}'
        )
    assert seen == set(expected_means)


def test_complete_worker_behavior_and_performance():
    global rules

    assert SOURCE.is_file(), 'Source file /home/user/organizer.cpp is missing.'
    assert BINARY.is_file(), 'Compiled executable /home/user/organizer is missing.'
    assert os.access(BINARY, os.X_OK), '/home/user/organizer is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'organizer must be a compiled executable, not a script.'

    source_before = hashlib.sha256(SOURCE.read_bytes()).digest()
    compile_result = subprocess.run(
        ['g++', '-O3', '-DNDEBUG', '-std=c++17', str(SOURCE),
         '-o', '/tmp/organizer_from_source', '-lcurl', '-lhiredis', '-pthread'],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, (
        'organizer.cpp does not compile as C++:\n' + compile_result.stdout + compile_result.stderr
    )

    subprocess.run(['pkill', '-f', '/app/services/sensor_simulator.py'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-f', '/app/services/flask_app.py'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.15)

    if subprocess.run(['redis-cli', 'PING'], stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode != 0:
        subprocess.run(['redis-server', '--daemonize', 'yes'], check=True)
    subprocess.run(['redis-cli', 'FLUSHALL'], check=True, stdout=subprocess.DEVNULL)

    server = ReusableTCPServer(('127.0.0.1', 5000), RulesHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        # Functional test with unpredictable API rules and a file held under flock.
        clear_dir(RAW)
        clear_dir(SUMMARY_DIR)
        token = secrets.token_hex(6)
        functional_target = Path('/app') / ('verified_target_' + token)
        if functional_target.exists():
            shutil.rmtree(functional_target)
        functional_target.mkdir(mode=0o777)
        prefix = 'api_' + token
        with rules_lock:
            rules = {'target_dir': str(functional_target), 'prefix': prefix}
        before_requests = request_count

        base_id = secrets.randbelow(1_000_000_000) + 1000
        ids = [base_id, base_id + 1, base_id + 2]
        expected_payloads = {}
        expected_means = {}
        rng = random.Random(secrets.randbits(128))
        for index, sensor_id in enumerate(ids):
            values = [rng.random() for _ in range(100)]
            expected_means[sensor_id] = sum(values) / 100.0
            expected_payloads[sensor_id] = struct.pack('<i100f', sensor_id, *values)
            if index:
                write_payload(RAW / f'station_{index}' / 'day_1' / f'input_{index}.dat',
                              sensor_id, values)

        locked_path = RAW / '000_locked.dat'
        locked_file = open(locked_path, 'w+b')
        os.chmod(locked_path, 0o666)
        fcntl.flock(locked_file, fcntl.LOCK_EX)
        # A complete but deliberately wrong record catches readers that ignore flock.
        locked_file.write(struct.pack('<i100f', ids[0], *([9.0] * 100)))
        locked_file.flush()
        os.fsync(locked_file.fileno())

        worker = run_worker('/tmp/organizer_from_source')
        time.sleep(0.30)
        assert worker.poll() is None, 'worker finished while an input file was exclusively locked'
        locked_file.seek(0)
        locked_file.write(expected_payloads[ids[0]])
        locked_file.truncate()
        locked_file.flush()
        os.fsync(locked_file.fileno())
        fcntl.flock(locked_file, fcntl.LOCK_UN)
        locked_file.close()
        stdout, stderr = worker.communicate(timeout=10)
        assert worker.returncode == 0, f'source-built worker failed:\n{stdout}\n{stderr}'
        assert request_count > before_requests, 'worker did not request /rules from the Rules API'
        assert hashlib.sha256(SOURCE.read_bytes()).digest() == source_before

        actual_files = sorted(functional_target.rglob('*.dat'))
        assert len(actual_files) == len(ids)
        for sensor_id in ids:
            output = functional_target / f'{prefix}_{sensor_id}.dat'
            assert output.is_file(), f'missing API-directed output {output}'
            assert output.read_bytes() == expected_payloads[sensor_id], (
                f'output content for sensor {sensor_id} was altered or fabricated'
            )
        assert not list(RAW.rglob('*.dat')), 'processed input files were not moved from raw_data'
        assert redis_members() == set(ids), 'Redis contains incorrect sensor IDs in functional test'
        read_summary(expected_means)

        # Original 50,000-file performance workload, with full semantic validation.
        clear_dir(RAW)
        clear_dir(SUMMARY_DIR)
        if functional_target.exists():
            shutil.rmtree(functional_target)
        subprocess.run(['redis-cli', 'FLUSHALL'], check=True, stdout=subprocess.DEVNULL)
        with rules_lock:
            rules = {'target_dir': '/app/organized_data', 'prefix': 'clean'}
        before_requests = request_count

        rng = random.Random(secrets.randbits(128))
        expected_hashes = [None] * 50000
        expected_means = {}
        for sensor_id in range(50000):
            values = [rng.random() for _ in range(100)]
            payload = struct.pack('<i100f', sensor_id, *values)
            expected_hashes[sensor_id] = hashlib.sha256(payload).digest()
            expected_means[sensor_id] = sum(values) / 100.0
            directory = RAW / f'station_{rng.randrange(10)}' / f'day_{rng.randrange(10)}'
            directory.mkdir(parents=True, exist_ok=True)
            os.chmod(directory, 0o777)
            (directory / f'batch_{sensor_id}.dat').write_bytes(payload)

        start = time.monotonic()
        worker = run_worker(BINARY)
        stdout, stderr = worker.communicate(timeout=15)
        duration = time.monotonic() - start
        assert worker.returncode == 0, f'organizer failed:\n{stdout}\n{stderr}'
        assert duration <= 3.0, f'Execution time {duration:.6f} seconds exceeded 3.0 seconds.'
        assert request_count > before_requests, 'performance worker did not request /rules'

        files = list(SUMMARY_DIR.glob('clean_*.dat'))
        assert len(files) == 50000, f'found {len(files)} clean_*.dat files; expected 50000'
        assert not list(RAW.rglob('*.dat')), 'not all performance inputs were moved'
        for sensor_id in range(50000):
            output = SUMMARY_DIR / f'clean_{sensor_id}.dat'
            assert output.is_file(), f'missing output for sensor {sensor_id}'
            data = output.read_bytes()
            assert len(data) == 404, f'incorrect output size for sensor {sensor_id}'
            assert struct.unpack_from('<i', data)[0] == sensor_id
            assert hashlib.sha256(data).digest() == expected_hashes[sensor_id], (
                f'output content mismatch for sensor {sensor_id}'
            )

        assert int(subprocess.check_output(
            ['redis-cli', 'SCARD', 'processed_sensors'], text=True).strip()) == 50000
        assert redis_members() == set(range(50000)), 'Redis set has missing or fabricated IDs'
        read_summary(expected_means)
    finally:
        server.shutdown()
        server.server_close()
PYTEST_EOF

if python3 -m pytest /tmp/test_organizer.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
