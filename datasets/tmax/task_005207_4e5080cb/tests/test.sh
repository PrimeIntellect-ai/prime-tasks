#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import threading
import time
import uuid

import pytest

SERVICES_DIR = '/home/user/services'
HEALTH = os.path.join(SERVICES_DIR, 'health_check.py')
MONITOR = os.path.join(SERVICES_DIR, 'log_monitor.sh')
START = os.path.join(SERVICES_DIR, 'start_services.sh')
APP_LOG = os.path.join(SERVICES_DIR, 'app.log')
PID_FILE = os.path.join(SERVICES_DIR, 'run.pid')
FLAG_FILE = os.path.join(SERVICES_DIR, 'consumer_success.flag')
CODES_FILE = os.path.join(SERVICES_DIR, 'critical_codes.txt')
PRODUCER = os.path.join(SERVICES_DIR, 'producer.py')
CONSUMER = os.path.join(SERVICES_DIR, 'consumer.py')

STATE = {}


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return ''


def matching_pids(path):
    result = []
    for name in os.listdir('/proc'):
        if name.isdigit() and path in cmdline(int(name)):
            result.append(int(name))
    return result


def stop_existing_services():
    pids = set(matching_pids(PRODUCER) + matching_pids(CONSUMER))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and any(os.path.exists(f'/proc/{p}') for p in pids):
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def free_port_socket():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 0))
    return s


def run_health_check_behavior_tests():
    # Keep the port bound but initially not listening. A correct checker must retry
    # until the delayed listener becomes available.
    listener = free_port_socket()
    port = listener.getsockname()[1]

    def delayed_listener():
        time.sleep(2.2)
        listener.listen(1)
        listener.settimeout(5)
        try:
            conn, _ = listener.accept()
            conn.close()
        finally:
            listener.close()

    thread = threading.Thread(target=delayed_listener, daemon=True)
    thread.start()
    started = time.monotonic()
    result = subprocess.run(
        ['python3', HEALTH, '127.0.0.1', str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
    )
    elapsed = time.monotonic() - started
    thread.join(timeout=6)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert 1.5 <= elapsed < 7, f'health check did not retry correctly; elapsed={elapsed:.2f}s'

    closed = free_port_socket()
    closed_port = closed.getsockname()[1]
    closed.close()
    started = time.monotonic()
    result = subprocess.run(
        ['python3', HEALTH, '127.0.0.1', str(closed_port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=19,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 1, 'health check must return 1 when the deadline expires'
    assert 13.5 <= elapsed <= 17.5, f'expected an approximately 15-second timeout, got {elapsed:.2f}s'


def run_log_monitor_synthetic_test():
    first = 'CODE_' + uuid.uuid4().hex[:10]
    second = 'CODE_' + uuid.uuid4().hex[:10]
    with open(APP_LOG, 'w') as f:
        f.write(f'2026-01-01 00:00:00,000 INFO SERVICE_X {first} payload CRITICAL later\n')
        f.write('2026-01-01 00:00:01,000 INFO SERVICE_X IGNORE ordinary message\n')
        f.write(f'2026-01-01 00:00:02,000 CRITICAL SERVICE_X {second} simulated failure\n')
    subprocess.run(['/bin/bash', MONITOR], check=True, timeout=5)
    with open(CODES_FILE) as f:
        found = [line.strip() for line in f if line.strip()]
    assert found == [first, second], f'log monitor produced {found}'


def run_lifecycle_integration():
    stop_existing_services()
    for path in (APP_LOG, PID_FILE, FLAG_FILE, CODES_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(START) as f:
        start_text = f.read()
    producer_pos = start_text.find(PRODUCER)
    health_pos = start_text.find(HEALTH)
    consumer_pos = start_text.find(CONSUMER)
    assert -1 not in (producer_pos, health_pos, consumer_pos), 'start_services.sh must invoke producer, health_check.py, and consumer'
    assert producer_pos < health_pos < consumer_pos, 'start_services.sh must sequence producer, health check, then consumer'

    proc = subprocess.Popen([START], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    began = time.monotonic()
    early_consumer = False
    while time.monotonic() - began < 3.5:
        if matching_pids(CONSUMER):
            early_consumer = True
            break
        if proc.poll() not in (None, 0):
            break
        time.sleep(0.05)
    assert not early_consumer, 'consumer started before the slow producer could become healthy'

    try:
        returncode = proc.wait(timeout=12)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail('start_services.sh did not finish after starting the services')
    assert returncode == 0, f'start_services.sh exited with {returncode}'

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and not os.path.isfile(FLAG_FILE):
        time.sleep(0.05)
    assert os.path.isfile(FLAG_FILE), 'consumer did not successfully communicate with producer'

    assert os.path.isfile(PID_FILE), f'{PID_FILE} is missing.'
    with open(PID_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 2, f'{PID_FILE} should contain exactly two lines (PIDs), found {len(lines)}.'
    for line in lines:
        assert line.strip().isdigit(), f"Expected PID to be numeric, got '{line}' in {PID_FILE}."
    producer_pid, consumer_pid = map(int, lines)
    assert PRODUCER in cmdline(producer_pid), 'first run.pid entry is not the running producer.py process'
    assert CONSUMER in cmdline(consumer_pid), 'second run.pid entry is not the running consumer.py process'

    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if os.path.isfile(APP_LOG) and 'CRITICAL' in open(APP_LOG).read():
            break
        time.sleep(0.05)
    subprocess.run(['/bin/bash', MONITOR], check=True, timeout=5)

    with open(APP_LOG) as f:
        critical_lines = [line.rstrip('\n') for line in f if 'CRITICAL' in line]
    expected = [line.split()[4] for line in critical_lines]
    assert expected == ['-', '-'], f'unexpected producer critical log records: {critical_lines}'
    STATE['expected_codes'] = expected


@pytest.fixture(scope='session', autouse=True)
def validated_state():
    assert os.path.isfile(HEALTH), f'{HEALTH} is missing.'
    assert os.path.isfile(MONITOR), f'{MONITOR} is missing.'
    assert os.path.isfile(START), f'{START} is missing.'
    run_health_check_behavior_tests()
    run_log_monitor_synthetic_test()
    run_lifecycle_integration()
    yield


def test_health_check_script_exists():
    """Check that health_check.py exists."""
    assert os.path.isfile(HEALTH), f'{HEALTH} is missing.'


def test_log_monitor_script_exists():
    """Check that log_monitor.sh exists."""
    assert os.path.isfile(MONITOR), f'{MONITOR} is missing.'


def test_run_pid_file():
    """Check that run.pid exists and contains exactly two lines (PIDs)."""
    assert os.path.isfile(PID_FILE), f'{PID_FILE} is missing.'
    with open(PID_FILE) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 2, f'{PID_FILE} should contain exactly two lines (PIDs), found {len(lines)}.'
    for line in lines:
        assert line.strip().isdigit(), f"Expected PID to be numeric, got '{line}' in {PID_FILE}."


def test_processes_running():
    """Check that both producer.py and consumer.py are running."""
    output = subprocess.check_output(['ps', 'aux']).decode('utf-8')
    assert 'producer.py' in output, 'producer.py is not running.'
    assert 'consumer.py' in output, 'consumer.py is not running. It may have crashed due to dependency failure.'


def test_consumer_success_flag():
    """Check that consumer_success.flag exists and contains 'OK'."""
    assert os.path.isfile(FLAG_FILE), f'{FLAG_FILE} is missing. Consumer did not successfully connect to producer.'
    with open(FLAG_FILE) as f:
        content = f.read().strip()
    assert content == 'OK', f"Expected 'OK' in {FLAG_FILE}, found '{content}'."


def test_critical_codes_file():
    """Check that critical_codes.txt contains column five from every CRITICAL line."""
    assert os.path.isfile(CODES_FILE), f'{CODES_FILE} is missing.'
    with open(CODES_FILE) as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]
    expected_codes = STATE['expected_codes']
    assert lines == expected_codes, f'Expected fifth-column values {expected_codes}, found {lines}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
