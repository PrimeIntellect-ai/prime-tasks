#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import signal
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

DETECTOR_PATH = '/home/user/detector.py'
CLEAN_CORPUS_PATHS = ['/home/user/corpora/clean', '/opt/verifier/corpora/clean']
EVIL_CORPUS_PATHS = ['/home/user/corpora/evil', '/opt/verifier/corpora/evil']
INGEST_URL = 'http://localhost:8080/ingest'
Q = chr(34)


def get_files_from_paths(paths):
    files = []
    for path in paths:
        if os.path.isdir(path):
            files.extend(glob.glob(os.path.join(path, '*')))
    return files


def run_detector(path):
    return subprocess.run(
        ['python3', DETECTOR_PATH, path], capture_output=True, timeout=5
    ).returncode


def post(data, timeout=5):
    req = urllib.request.Request(
        INGEST_URL,
        data=data,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.headers


def reference_valid(raw):
    def reject_constant(value):
        raise ValueError(value)

    try:
        value = json.loads(raw.decode('utf-8'), parse_constant=reject_constant)
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return False

    def valid(item):
        if isinstance(item, float):
            return math.isfinite(item)
        if isinstance(item, str):
            try:
                item.encode('utf-8')
                return True
            except UnicodeEncodeError:
                return False
        if isinstance(item, dict):
            return all(valid(key) and valid(child) for key, child in item.items())
        if isinstance(item, list):
            return all(valid(child) for child in item)
        return True

    return valid(value)


def make_generated_cases():
    nonce = secrets.token_hex(12)
    key = 'metric_' + secrets.token_hex(8)
    clean_objects = [
        {key: 0.0, 'tag': nonce},
        {'outer_' + nonce: {'samples': [1, -2, 3.5, {'value': 1e307}]}},
        {'text': 'NaN Infinity -Infinity are ordinary text', 'id': nonce},
        {'unicode': 'snowman ☃ and emoji 😀', 'enabled': True, 'nothing': None},
        {'Infinity': 17, 'NaN': 'finite', 'nested': [{'x': -0.0}]},
    ]
    candidates = []
    for index, obj in enumerate(clean_objects):
        candidates.append(json.dumps(
            obj,
            ensure_ascii=(index % 2 == 0),
            separators=(',', ':') if index % 2 else None,
        ).encode('utf-8'))

    candidates.extend([
        ('{  ' + Q + key + Q + ' : NaN, ' + Q + 'id' + Q + ':' + Q + nonce + Q + ' }').encode(),
        ('{' + Q + 'outer_' + nonce + Q + ':{' + Q + key + Q + ': Infinity}}').encode(),
        ('{' + Q + 'items' + Q + ':[0,{' + Q + key + Q + ':-Infinity},2]}').encode(),
        ('{' + Q + key + Q + ':9e999}').encode(),
        ('{' + Q + 'nested' + Q + ':{' + Q + key + Q + ':-7e999}}').encode(),
        ('{' + Q + key + Q + ':' + Q + 'prefix\\ud800suffix' + Q + '}').encode(),
        ('{' + Q + 'items' + Q + ':[' + Q + 'ok' + Q + ',' + Q + '\\udfff' + Q + ']}').encode(),
        ('{' + Q + key + Q + ':1,}').encode(),
        ('{' + Q + key + Q + ':').encode(),
        ('{' + Q + 'valid_pair' + Q + ':' + Q + '\\ud83d\\ude00' + Q + '}').encode(),
    ])

    directory = tempfile.mkdtemp(prefix='runtime-validation-')
    clean = []
    evil = []
    for index, raw in enumerate(candidates):
        path = os.path.join(directory, secrets.token_hex(10) + '.json')
        with open(path, 'wb') as handle:
            handle.write(raw)
        (clean if reference_valid(raw) else evil).append((path, raw))
    assert len(clean) >= 6
    assert len(evil) >= 8
    return clean, evil


GENERATED_CLEAN, GENERATED_EVIL = make_generated_cases()


def test_detector_exists():
    assert os.path.isfile(DETECTOR_PATH), f'Detector script not found at {DETECTOR_PATH}'


def test_detector_clean_corpus():
    clean_files = get_files_from_paths(CLEAN_CORPUS_PATHS)
    assert clean_files, 'No clean corpus files found.'
    failed = [path for path in clean_files if run_detector(path) != 0]
    assert not failed, f'{len(failed)} clean corpus files were rejected: {failed}'


def test_detector_evil_corpus():
    evil_files = get_files_from_paths(EVIL_CORPUS_PATHS)
    assert evil_files, 'No evil corpus files found.'
    failed = [path for path in evil_files if run_detector(path) != 1]
    assert not failed, f'{len(failed)} evil corpus files bypassed detection: {failed}'


def test_end_to_end_clean_corpus():
    clean_files = get_files_from_paths(CLEAN_CORPUS_PATHS)
    assert clean_files, 'No clean corpus files found.'
    failed = []
    for path in clean_files:
        with open(path, 'rb') as handle:
            status, _, _ = post(handle.read())
        if status != 200:
            failed.append((path, status))
    assert not failed, f'Clean corpus failed end-to-end: {failed}'


def test_end_to_end_evil_corpus():
    evil_files = get_files_from_paths(EVIL_CORPUS_PATHS)
    assert evil_files, 'No evil corpus files found.'
    failed = []
    for path in evil_files:
        with open(path, 'rb') as handle:
            try:
                status, _, _ = post(handle.read())
            except Exception as error:
                failed.append((path, repr(error)))
                continue
        if status != 400:
            failed.append((path, status))
    assert not failed, f'Evil corpus bypassed the ingestion filter: {failed}'


def test_detector_runtime_generated_cases():
    failed = []
    for path, _ in GENERATED_CLEAN:
        if run_detector(path) != 0:
            failed.append((path, 'expected clean'))
    for path, _ in GENERATED_EVIL:
        if run_detector(path) != 1:
            failed.append((path, 'expected evil'))
    assert not failed, f'Runtime-generated detector cases failed: {failed}'


def test_end_to_end_runtime_generated_clean():
    failed = []
    for path, raw in GENERATED_CLEAN:
        try:
            status, _, _ = post(raw)
        except Exception as error:
            failed.append((path, repr(error)))
            continue
        if status != 200:
            failed.append((path, status))
    assert not failed, f'Runtime-generated clean requests failed: {failed}'


def test_end_to_end_runtime_generated_evil():
    failed = []
    for path, raw in GENERATED_EVIL:
        try:
            status, _, _ = post(raw)
        except Exception as error:
            failed.append((path, repr(error)))
            continue
        if status != 400:
            failed.append((path, status))
    assert not failed, f'Runtime-generated evil requests bypassed filtering: {failed}'


def listener_inodes(port):
    wanted = format(port, '04X')
    found = set()
    for table in ['/proc/net/tcp', '/proc/net/tcp6']:
        try:
            with open(table) as handle:
                rows = handle.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                found.add(fields[9])
    return found


def kill_port_listener(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = os.path.join('/proc', entry, 'fd')
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(entry), signal.SIGKILL)
                break
    deadline = time.time() + 3
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(port), f'Could not replace listener on port {port}'


def test_clean_requests_are_really_forwarded_to_backend():
    kill_port_listener(5001)
    response_token = secrets.token_hex(24)
    received = []

    class ProbeHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            received.append((self.path, body, self.headers.get('Content-Type')))
            reply = ('probe-response-' + response_token).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('X-Verifier-Probe', response_token)
            self.send_header('Content-Length', str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        def log_message(self, *args):
            pass

    class ProbeServer(ThreadingHTTPServer):
        allow_reuse_address = True

    server = ProbeServer(('127.0.0.1', 5001), ProbeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    sent = []
    try:
        for _ in range(3):
            raw = json.dumps({
                'probe_' + secrets.token_hex(8): secrets.token_hex(20),
                'value': 0.125,
            }).encode()
            sent.append(raw)
            status, body, headers = post(raw)
            assert status == 200
            assert body == ('probe-response-' + response_token).encode()
            assert headers.get('X-Verifier-Probe') == response_token
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert [item[0] for item in received] == ['/process'] * len(sent)
    assert [item[1] for item in received] == sent
    assert all(item[2] == 'application/json' for item in received)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
