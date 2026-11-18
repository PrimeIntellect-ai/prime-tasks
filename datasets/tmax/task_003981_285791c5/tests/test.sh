#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = '/home/user/microservices'
CONFIG = BASE + '/config.ini'


def read_stats():
    with urllib.request.urlopen('http://127.0.0.1:8003/stats', timeout=2) as response:
        return json.loads(response.read().decode('utf-8'))


def process_running(script_name):
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='ignore')
            cwd = os.readlink(f'/proc/{entry}/cwd')
        except (OSError, PermissionError):
            continue
        if script_name in cmdline and (BASE in cmdline or cwd == BASE):
            return True
    return False


def kill_listener(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                    state = fields[3]
                    if local_port == port and state == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(entry))
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        if all(not os.path.exists(f'/proc/{pid}') for pid in victims):
            break
        time.sleep(0.05)
    for pid in victims:
        if os.path.exists(f'/proc/{pid}'):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def test_config_updated():
    assert os.path.isfile(CONFIG), f'The config file {CONFIG} is missing.'
    config = configparser.ConfigParser()
    config.read(CONFIG)
    assert 'Emitter' in config, '[Emitter] section missing in config.ini'
    assert config['Emitter'].get('processor_port') == '8002', 'The processor_port in config.ini was not updated to 8002.'
    assert config['Processor'].get('aggregator_port') == '9003', 'The Processor configuration must still target port 9003.'
    assert config['Aggregator'].get('listen_port') == '8003', 'The Aggregator configuration must still listen on port 8003.'


def test_apply_fixes_script_exists_and_is_idempotent():
    script_path = '/home/user/apply_fixes.py'
    assert os.path.isfile(script_path), f'The script {script_path} is missing.'

    with open(CONFIG, 'rb') as f:
        original = f.read()
    test_config = b'''[Emitter]\nprocessor_host = 127.0.0.1\nprocessor_port = 8080\n\n[Processor]\naggregator_host = 127.0.0.1\naggregator_port = 9003\n\n[Aggregator]\nlisten_host = 127.0.0.1\nlisten_port = 8003\n'''
    try:
        with open(CONFIG, 'wb') as f:
            f.write(test_config)
        first = subprocess.run(['python3', script_path], cwd='/home/user', capture_output=True, text=True, timeout=10)
        assert first.returncode == 0, f'apply_fixes.py failed: {first.stderr}'
        with open(CONFIG, 'rb') as f:
            first_state = f.read()

        parsed = configparser.ConfigParser()
        parsed.read_string(first_state.decode())
        assert parsed['Emitter'].get('processor_port') == '8002'
        assert parsed['Processor'].get('aggregator_port') == '9003'
        assert parsed['Aggregator'].get('listen_port') == '8003'

        second = subprocess.run(['python3', script_path], cwd='/home/user', capture_output=True, text=True, timeout=10)
        assert second.returncode == 0, f'Second apply_fixes.py run failed: {second.stderr}'
        with open(CONFIG, 'rb') as f:
            second_state = f.read()
        assert second_state == first_state, 'apply_fixes.py is not strictly idempotent: the second run changed config.ini.'
    finally:
        with open(CONFIG, 'wb') as f:
            f.write(original)


def test_services_are_running_and_pipeline_is_flowing():
    for script in ('emitter.py', 'processor.py', 'aggregator.py'):
        assert process_running(script), f'{script} is not running from {BASE}.'

    before = read_stats().get('total_received')
    assert isinstance(before, int), 'Aggregator stats did not contain an integer total_received.'
    deadline = time.time() + 5
    after = before
    while time.time() < deadline and after <= before:
        time.sleep(0.4)
        after = read_stats().get('total_received')
    assert isinstance(after, int) and after > before, 'The live emitter/processor/aggregator pipeline is not delivering new transactions.'


def test_first_transaction_extracted():
    log_path = BASE + '/logs/aggregator.log'
    txt_path = '/home/user/first_transaction.txt'
    assert os.path.isfile(log_path), f'The log file {log_path} is missing. Did the services run?'
    assert os.path.isfile(txt_path), f'The output file {txt_path} is missing.'

    expected_uuid = None
    with open(log_path, 'r') as f:
        for line in f:
            if '[INFO] - SUCCESS - Transaction ID:' in line:
                match = re.search(r'Transaction ID: ([a-f0-9\-]+) -', line)
                if match:
                    expected_uuid = match.group(1)
                    break
    assert expected_uuid is not None, 'Could not find a successful transaction in aggregator.log.'

    with open(txt_path, 'r') as f:
        actual_uuid = f.read().strip()
    assert actual_uuid == expected_uuid, f'The UUID in {txt_path} ({actual_uuid}) does not match the first transaction in the log ({expected_uuid}).'
    assert str(uuid.UUID(actual_uuid)) == actual_uuid, 'first_transaction.txt does not contain only a canonical UUID.'


def test_tunnel_is_functional():
    kill_listener(8003)
    token = uuid.uuid4().hex

    class ProbeHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/probe':
                body = token.encode()
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()
        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 8003), ProbeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        deadline = time.time() + 4
        last_error = None
        while time.time() < deadline:
            try:
                with urllib.request.urlopen('http://127.0.0.1:9003/probe', timeout=1) as response:
                    assert response.read().decode() == token
                    return
            except Exception as exc:
                last_error = exc
                time.sleep(0.2)
        assert False, f'Port 9003 did not forward to port 8003: {last_error}'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_monitor_script_exists():
    script_path = '/home/user/monitor.py'
    assert os.path.isfile(script_path), f'The script {script_path} is missing.'


def test_monitor_handles_errors_polls_and_exits():
    script_path = '/home/user/monitor.py'
    result_path = '/home/user/monitor_result.json'
    kill_listener(8003)
    try:
        os.remove(result_path)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(['python3', script_path], cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    server = None
    thread = None
    request_times = []
    try:
        time.sleep(1.3)
        assert proc.poll() is None, 'monitor.py crashed while the health endpoint was unavailable.'
        assert not os.path.exists(result_path), 'monitor.py reported success without reaching total_received >= 5.'

        class StatsHandler(BaseHTTPRequestHandler):
            calls = 0
            def do_GET(self):
                assert self.path == '/stats'
                type(self).calls += 1
                request_times.append(time.monotonic())
                if type(self).calls == 1:
                    time.sleep(1.5)
                    count = 0
                elif type(self).calls == 2:
                    count = 4
                else:
                    count = 5
                body = json.dumps({'total_received': count}).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except BrokenPipeError:
                    pass
            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 8003), StatsHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        returncode = proc.wait(timeout=10)
        stdout, stderr = proc.communicate()
        assert returncode == 0, f'monitor.py did not exit successfully: {stdout} {stderr}'
        assert len(request_times) >= 3, 'monitor.py did not continue polling through values below 5.'
        for earlier, later in zip(request_times, request_times[1:]):
            assert later - earlier >= 0.75, 'monitor.py did not poll at approximately one-second intervals.'
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=2)


def test_monitor_result():
    result_path = '/home/user/monitor_result.json'
    assert os.path.isfile(result_path), f'The result file {result_path} is missing.'
    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'The file {result_path} does not contain valid JSON.'
    assert data.get('status') == 'success', f"Expected status 'success' in {result_path}, got {data.get('status')}."
    assert data.get('count') == 5, f"Expected count 5 in {result_path}, got {data.get('count')}."
    assert data == {'status': 'success', 'count': 5}, 'monitor_result.json contains unexpected fields or values.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
