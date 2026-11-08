#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import stat
import subprocess
import tarfile
import time

import pytest

TRACKER = '/home/user/config_tracker.py'
MOUNT_DIR = '/home/user/config_mount'
ARCHIVE_DIR = '/home/user/archives'
ARCHIVE_PATH = os.path.join(ARCHIVE_DIR, 'config_history.tar.gz')
WEBHOOK_LOG = '/tmp/config_tracker_webhooks.jsonl'


def prune_nulls(value):
    if isinstance(value, dict):
        return {k: prune_nulls(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [prune_nulls(v) for v in value if v is not None]
    return value


def read_webhooks():
    messages = []
    if not os.path.exists(WEBHOOK_LOG):
        return messages
    with open(WEBHOOK_LOG, 'r', encoding='utf-8') as handle:
        for line in handle:
            try:
                messages.append(json.loads(line))
            except (ValueError, TypeError):
                pass
    return messages


def inspect_archive(expected):
    if not os.path.exists(ARCHIVE_PATH):
        raise AssertionError(f'Archive file not found at {ARCHIVE_PATH}.')
    mode = os.lstat(ARCHIVE_PATH).st_mode
    assert stat.S_ISREG(mode), 'Archive path must be a regular file.'

    with tarfile.open(ARCHIVE_PATH, mode='r:gz') as archive:
        members = archive.getmembers()
        assert len(members) == 50, f'Expected 50 archive members, found {len(members)}.'
        assert all(member.isfile() for member in members), 'All archive members must be regular files.'

        by_basename = {}
        for member in members:
            basename = os.path.basename(member.name)
            assert basename not in by_basename, f'Duplicate archived file: {basename}'
            by_basename[basename] = member

        assert set(by_basename) == set(expected), 'Archive does not contain exactly the 50 generated JSON files.'

        for filename, wanted in expected.items():
            extracted = archive.extractfile(by_basename[filename])
            assert extracted is not None
            raw = extracted.read()
            parsed = json.loads(raw.decode('utf-8'))
            assert parsed == prune_nulls(wanted), f'Incorrect optimized content for {filename}.'
            compact = json.dumps(parsed, separators=(',', ':'), ensure_ascii=True).encode('utf-8')
            assert raw == compact, f'{filename} was not stored as compact JSON.'


def wait_for_archive(expected, timeout):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            inspect_archive(expected)
            return
        except (AssertionError, OSError, EOFError, tarfile.TarError, ValueError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.25)
    raise AssertionError(f'Archive did not reach the expected state: {last_error}')


def wait_for_webhooks(predicate, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        messages = read_webhooks()
        if predicate(messages):
            return messages
        time.sleep(0.2)
    messages = read_webhooks()
    raise AssertionError(f'Expected webhook requests were not observed. Received: {messages!r}')


def test_config_tracker_archive_updates_and_webhooks():
    assert os.path.exists(TRACKER), f'{TRACKER} was not found.'
    assert stat.S_ISREG(os.lstat(TRACKER).st_mode), f'{TRACKER} must be a regular file.'

    os.makedirs(MOUNT_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for name in os.listdir(MOUNT_DIR):
        path = os.path.join(MOUNT_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    if os.path.lexists(ARCHIVE_PATH):
        os.unlink(ARCHIVE_PATH)
    if os.path.exists(WEBHOOK_LOG):
        os.unlink(WEBHOOK_LOG)

    server_source = r'''
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

log_path = '/tmp/config_tracker_webhooks.jsonl'
lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        if self.path != '/webhook':
            self.send_response(404)
            self.end_headers()
            return
        try:
            payload = json.loads(body.decode('utf-8'))
            with lock:
                with open(log_path, 'a', encoding='utf-8') as handle:
                    handle.write(json.dumps(payload, separators=(',', ':')) + '\n')
                    handle.flush()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        except Exception:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 5000), Handler).serve_forever()
'''
    server = subprocess.Popen(['python3', '-c', server_source], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    agent = None
    agent_pgid = None
    try:
        deadline = time.time() + 5
        while time.time() < deadline and server.poll() is None:
            import socket
            try:
                with socket.create_connection(('127.0.0.1', 5000), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        assert server.poll() is None, 'Could not start the webhook receiver on port 5000.'

        subprocess.run(['nginx'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

        if os.path.exists('/home/user/run.sh'):
            agent = subprocess.Popen(['bash', '/home/user/run.sh'], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
        else:
            agent = subprocess.Popen(['python3', TRACKER], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
        agent_pgid = os.getpgid(agent.pid)
        time.sleep(1)

        nonce = secrets.token_hex(12)
        expected = {}
        for i in range(50):
            data = {
                'config_id': i,
                'nonce': f'{nonce}-{i}',
                'description': f'Configuration file number {i}',
                'settings': {
                    'enabled': i % 2 == 0,
                    'timeout': 300 + i,
                    'features': {
                        'beta': None,
                        'experimental': [None, 'flag1', {'inner': None, 'value': i}, 'flag2', None],
                        'legacy': None
                    }
                },
                'padding_for_size': ' ' * 500,
                'empty_field': None
            }
            filename = f'config_{i}.json'
            expected[filename] = data
            with open(os.path.join(MOUNT_DIR, filename), 'w', encoding='utf-8') as handle:
                json.dump(data, handle, indent=4)
            time.sleep(0.1)

        wait_for_archive(expected, 25)
        initial_names = set(expected)
        wait_for_webhooks(
            lambda msgs: initial_names.issubset({m.get('latest_update') for m in msgs if isinstance(m, dict)}),
            15
        )

        updated = dict(expected['config_7.json'])
        updated['nonce'] = secrets.token_hex(20)
        updated['description'] = 'modified configuration seven'
        updated['new_nested_value'] = {'drop': None, 'keep': [1, None, {'x': None, 'y': 'kept'}]}
        expected['config_7.json'] = updated
        update_path = os.path.join(MOUNT_DIR, 'config_7.json')
        with open(update_path, 'w', encoding='utf-8') as handle:
            json.dump(updated, handle, indent=6)

        wait_for_archive(expected, 20)
        final_size = os.path.getsize(ARCHIVE_PATH)

        # Preserve the original metric requirement.
        assert final_size < 15000, (
            f'Metric failed: Archive size {final_size} >= 15000 bytes. '
            'Ensure JSON is minified, null values are removed, and gzip compression is used.'
        )

        messages = wait_for_webhooks(
            lambda msgs: any(
                isinstance(m, dict)
                and m.get('latest_update') == 'config_7.json'
                and m.get('archive_size') == final_size
                for m in msgs
            ),
            15
        )
        for message in messages:
            assert isinstance(message, dict), 'Webhook payload must be a JSON object.'
            assert set(message) == {'latest_update', 'archive_size'}, 'Webhook payload has incorrect fields.'
            assert isinstance(message['latest_update'], str)
            assert isinstance(message['archive_size'], int) and not isinstance(message['archive_size'], bool)
            assert message['archive_size'] > 0

        matching_updates = [m for m in messages if m.get('latest_update') == 'config_7.json']
        assert len(matching_updates) >= 2, 'No webhook was observed for both creation and modification of config_7.json.'
    finally:
        if agent_pgid is not None:
            try:
                os.killpg(agent_pgid, signal.SIGTERM)
                time.sleep(0.5)
                os.killpg(agent_pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
