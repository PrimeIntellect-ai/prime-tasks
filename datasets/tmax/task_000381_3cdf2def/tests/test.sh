#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import pwd
import signal
import socket
import stat
import subprocess
import time
import uuid

import pytest
import redis
import requests


def is_valid_uuid(val):
    try:
        parsed = uuid.UUID(str(val), version=4)
        return parsed.version == 4
    except (ValueError, TypeError, AttributeError):
        return False


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\x00', b' ').decode(errors='ignore')
    except (IOError, OSError):
        return ''


def kill_matching(text):
    me = os.getpid()
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == me:
            continue
        if text in cmdline(entry):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        if not any(os.path.exists(f'/proc/{pid}') for pid in victims):
            return
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def descendants(root_pid):
    parents = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/status') as f:
                fields = dict(line.split(':', 1) for line in f if ':' in line)
            parents[int(entry)] = int(fields['PPid'].strip())
        except (IOError, OSError, KeyError, ValueError):
            pass
    found = set()
    frontier = {root_pid}
    while frontier:
        children = {pid for pid, ppid in parents.items() if ppid in frontier and pid not in found}
        found.update(children)
        frontier = children
    return found


def wait_http():
    deadline = time.time() + 8
    last = None
    while time.time() < deadline:
        try:
            response = requests.get('http://127.0.0.1:8080/metrics', timeout=0.5)
            if response.status_code == 200:
                return
            last = RuntimeError(f'HTTP {response.status_code}')
        except Exception as exc:
            last = exc
        time.sleep(0.1)
    pytest.fail(f'Metrics API did not start: {last}')


def connect_alert_socket():
    deadline = time.time() + 8
    last = None
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        try:
            sock.connect(('127.0.0.1', 9000))
            return sock
        except Exception as exc:
            last = exc
            sock.close()
            time.sleep(0.1)
    pytest.fail(f'Failed to connect to TCP server on localhost:9000: {last}')


@pytest.fixture(scope='session')
def state():
    processor_path = '/home/user/processor.py'
    assert os.path.exists(processor_path), 'processor.py was not created'
    assert not os.path.islink(processor_path), 'processor.py must be a regular submitted file'
    assert stat.S_ISREG(os.stat(processor_path).st_mode), 'processor.py is not a regular file'
    assert os.path.getsize(processor_path) > 0, 'processor.py is empty'

    # Supply the services that the task states are automatically available.
    try:
        probe = redis.Redis(host='127.0.0.1', port=6379, db=0)
        probe.ping()
    except Exception:
        subprocess.run(['redis-server', '--daemonize', 'yes'], check=True)

    r = redis.Redis(host='127.0.0.1', port=6379, db=0, decode_responses=True)
    deadline = time.time() + 5
    while True:
        try:
            r.ping()
            break
        except Exception:
            if time.time() >= deadline:
                pytest.fail('Redis did not start on localhost:6379')
            time.sleep(0.1)

    # Exclude random emitter traffic and previous processor/API instances so the
    # expected result is derived solely from this verifier's controlled input.
    kill_matching('/app/emitter.py')
    kill_matching('/home/user/processor.py')
    kill_matching('/app/api.py')
    r.flushdb()

    api_log = open('/tmp/verifier_api.log', 'wb')
    subprocess.Popen(
        ['python3', '/app/api.py'],
        stdout=api_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_http()

    account = pwd.getpwnam('user')
    processor_log = open('/tmp/verifier_processor.log', 'wb')

    def become_user():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    processor = subprocess.Popen(
        ['python3', processor_path],
        cwd='/home/user',
        env={**os.environ, 'HOME': '/home/user'},
        stdout=processor_log,
        stderr=subprocess.STDOUT,
        preexec_fn=become_user,
        start_new_session=True,
    )

    sock = connect_alert_socket()
    sock.setblocking(False)
    time.sleep(0.4)  # Allow the server to accept this already-connected client.

    # Clear anything produced during startup, then build an independently
    # calculated workload containing valid and invalid records.
    r.delete('raw_logs')
    r.delete('metrics:counts')

    token = uuid.uuid4().hex[:10]
    services = [f'audit-{token}-a', f'audit-{token}-b', f'audit-{token}-c']
    valid_raw = []
    expected_metrics = collections.Counter()
    expected_alerts = []

    levels = ['INFO'] * 600 + ['WARN'] * 600 + ['CRITICAL'] * 5
    for i, level in enumerate(levels):
        record = {
            'id': str(uuid.uuid4()),
            'timestamp': 1700000000.0 + i,
            'service': services[i % len(services)],
            'level': level,
            'msg': f'controlled message {i}',
        }
        # Deliberately retain visible non-canonical spacing in CRITICAL records.
        if level == 'CRITICAL':
            raw = json.dumps(record, separators=(', ', ' : '), ensure_ascii=False)
            expected_alerts.append(raw)
        else:
            raw = json.dumps(record, separators=(',', ':'))
        valid_raw.append(raw)
        expected_metrics[f"{record['service']}_{level}"] += 1

    base = {
        'id': str(uuid.uuid4()),
        'timestamp': 1700009999.0,
        'service': services[0],
        'level': 'CRITICAL',
        'msg': 'must be discarded',
    }
    invalid_raw = []
    extra = dict(base)
    extra['extra'] = True
    invalid_raw.append(json.dumps(extra))
    missing = dict(base)
    del missing['msg']
    invalid_raw.append(json.dumps(missing))
    bad_level = dict(base)
    bad_level['level'] = 'DEBUG'
    invalid_raw.append(json.dumps(bad_level))
    bad_level2 = dict(base)
    bad_level2['level'] = 'FATAL'
    invalid_raw.append(json.dumps(bad_level2))
    bad_uuid = dict(base)
    bad_uuid['id'] = 'not-a-uuid'
    invalid_raw.append(json.dumps(bad_uuid))
    wrong_uuid_version = dict(base)
    wrong_uuid_version['id'] = str(uuid.uuid1())
    invalid_raw.append(json.dumps(wrong_uuid_version))
    invalid_raw.append('{not valid json')
    invalid_raw.append(json.dumps(['not', 'an', 'object']))

    pipe = r.pipeline()
    for raw in valid_raw + invalid_raw:
        pipe.rpush('raw_logs', raw)
    pipe.execute()

    messages = []
    buffer = ''
    max_children = 0
    final_metrics = None
    completed_at = None
    deadline = time.time() + 15

    while time.time() < deadline:
        assert processor.poll() is None, 'processor.py exited while processing logs'
        max_children = max(max_children, len(descendants(processor.pid)))

        try:
            chunk = sock.recv(65536)
            if chunk:
                buffer += chunk.decode('utf-8')
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if line:
                        messages.append(line)
        except BlockingIOError:
            pass

        try:
            response = requests.get('http://127.0.0.1:8080/metrics', timeout=0.5)
            if response.status_code == 200:
                final_metrics = response.json()
        except Exception:
            pass

        if final_metrics == dict(expected_metrics) and r.llen('raw_logs') == 0:
            if completed_at is None:
                completed_at = time.time()
            if time.time() - completed_at >= 1.0:
                break
        else:
            completed_at = None
        time.sleep(0.03)

    sock.close()
    return {
        'processor': processor,
        'messages': messages,
        'expected_alerts': expected_alerts,
        'expected_metrics': dict(expected_metrics),
        'max_children': max_children,
        'queue_length': r.llen('raw_logs'),
    }


def test_processor_running(state):
    process_found = False
    for pid in os.listdir('/proc'):
        if pid.isdigit():
            try:
                with open(f'/proc/{pid}/cmdline', 'r') as f:
                    command = f.read()
                    if 'processor.py' in command:
                        process_found = True
                        break
            except (IOError, OSError):
                continue
    assert process_found, 'processor.py is not running in the background'
    assert state['processor'].poll() is None, 'the submitted processor is not running'
    assert state['max_children'] >= 2, 'processor.py did not use multiple worker processes'
    assert state['queue_length'] == 0, 'processor did not consume all raw_logs entries'


def test_tcp_broadcast(state):
    messages = state['messages']
    assert len(messages) >= 5, f"Expected at least 5 CRITICAL messages over TCP, got {len(messages)}"

    for msg in messages:
        try:
            log_data = json.loads(msg)
        except json.JSONDecodeError:
            pytest.fail(f'Received invalid JSON over TCP: {msg}')
        assert 'level' in log_data, f"Log missing 'level' key: {log_data}"
        assert log_data['level'] == 'CRITICAL', f"Expected level CRITICAL, got {log_data['level']}"
        assert 'id' in log_data, f"Log missing 'id' key: {log_data}"
        assert is_valid_uuid(log_data['id']), f"Invalid UUID4 in log: {log_data['id']}"

    assert collections.Counter(messages) == collections.Counter(state['expected_alerts']), \
        'TCP output did not exactly preserve and broadcast each valid raw CRITICAL record'


def test_metrics_api(state):
    try:
        response = requests.get('http://127.0.0.1:8080/metrics', timeout=5)
    except Exception as exc:
        pytest.fail(f'Failed to connect to API on localhost:8080: {exc}')

    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
    try:
        metrics = response.json()
    except ValueError:
        pytest.fail('API response is not valid JSON')
    assert isinstance(metrics, dict), 'Metrics response should be a JSON object'

    levels_found = set()
    for key in metrics.keys():
        assert not key.endswith('_DEBUG'), f'Found invalid level in metrics: {key}'
        assert not key.endswith('_FATAL'), f'Found invalid level in metrics: {key}'
        if key.endswith('_INFO'):
            levels_found.add('INFO')
        elif key.endswith('_WARN'):
            levels_found.add('WARN')
        elif key.endswith('_CRITICAL'):
            levels_found.add('CRITICAL')

    assert 'INFO' in levels_found, 'Metrics missing INFO logs'
    assert 'WARN' in levels_found, 'Metrics missing WARN logs'
    assert 'CRITICAL' in levels_found, 'Metrics missing CRITICAL logs'
    assert metrics == state['expected_metrics'], \
        f"Metrics did not exactly match validated raw_logs: expected {state['expected_metrics']}, got {metrics}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
