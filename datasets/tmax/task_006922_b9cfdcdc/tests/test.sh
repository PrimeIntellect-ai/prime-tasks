#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import socket
import subprocess
import time
import urllib.request

import pytest

PROXY_DIR = pathlib.Path('/home/user/proxy')


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                try:
                    found_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if found_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def kill_listeners(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(('127.0.0.1', port)) == 0:
                return
        time.sleep(0.05)
    pytest.fail(f'Port {port} did not become ready')


def test_ssh_tunnel_running():
    """Verify that the SSH tunnel is listening on 127.0.0.1:9090."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(('127.0.0.1', 9090))
        assert result == 0, 'SSH tunnel is not listening on 127.0.0.1:9090.'

    pids = listener_pids(9090)
    assert pids, 'No process owns the port 9090 listener.'
    valid = False
    for pid in pids:
        try:
            exe = os.path.realpath(f'/proc/{pid}/exe')
            cmd = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        except OSError:
            continue
        if os.path.basename(exe) == 'ssh' and ('9090:127.0.0.1:8080' in cmd or '9090:localhost:8080' in cmd):
            valid = True
    assert valid, 'Port 9090 is not owned by an ssh process with the required local forwarding rule.'


def test_config_file_exists_and_valid():
    """Verify that the config.json file exists and has the correct content."""
    config_path = '/home/user/proxy/config.json'
    assert os.path.exists(config_path), f'Config file {config_path} does not exist.'
    with open(config_path, 'r') as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('config.json is not valid JSON.')

    assert config.get('target_url') == 'http://127.0.0.1:9090', 'Incorrect target_url in config.json'
    assert config.get('alert_threshold_cpu') == 85, 'Incorrect alert_threshold_cpu in config.json'
    assert config.get('smtp_server') == '127.0.0.1:1025', 'Incorrect smtp_server in config.json'
    assert config.get('alert_email') == 'alerts@dashboard.local', 'Incorrect alert_email in config.json'


def test_go_proxy_server_running():
    """Verify that the Go proxy server is listening on 127.0.0.1:7070."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(('127.0.0.1', 7070))
        assert result == 0, 'Go proxy server is not listening on 127.0.0.1:7070.'

    source = PROXY_DIR / 'main.go'
    binary = PROXY_DIR / 'proxy_server'
    assert source.is_file() and source.stat().st_size > 0, 'main.go is missing or empty.'
    assert binary.is_file(), 'proxy_server is missing.'
    assert os.access(binary, os.X_OK), 'proxy_server is not executable.'
    assert binary.read_bytes()[:4] == b'\x7fELF', 'proxy_server is not an ELF executable.'


def test_alert_log_created_and_valid():
    """Verify that the alert.log file was created and contains the expected log entry."""
    log_path = '/home/user/proxy/alert.log'
    assert os.path.exists(log_path), f'Alert log {log_path} does not exist. Did the proxy trigger the alert?'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert 'ALERT TRIGGERED: cpu=95' in content, f'Expected alert log entry not found in {log_path}.'


def test_email_sent_and_valid():
    """Verify that the email was sent with the correct details."""
    email_log_path = '/home/user/proxy/email_received.log'
    assert os.path.exists(email_log_path), f'Email log {email_log_path} does not exist. Was the email sent?'
    with open(email_log_path, 'r') as f:
        email_data = f.read()

    assert 'FROM:proxy@dashboard.local' in email_data, 'Email FROM address is incorrect or missing.'
    assert 'TO:alerts@dashboard.local' in email_data, 'Email TO address is incorrect or missing.'
    assert 'High CPU Alert' in email_data, 'Email Subject is incorrect or missing.'
    assert 'CPU usage is at 95%' in email_data, 'Email Body is incorrect or missing.'


def run_behavioral_cases(executable, expected_responses):
    alert_log = PROXY_DIR / 'alert.log'
    capture_log = pathlib.Path('/tmp/verifier_smtp.jsonl')
    alert_log.write_text('')
    capture_log.write_text('')

    proc = subprocess.Popen(
        [str(executable)], cwd=str(PROXY_DIR),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_port(7070)
        assert proc.poll() is None, f'{executable} exited before serving requests.'

        with urllib.request.urlopen('http://127.0.0.1:7070/api/metrics', timeout=5) as response:
            low_body = response.read()
            assert response.status == 200
        assert low_body == expected_responses[0].encode(), 'Proxy did not return the backend response unchanged.'
        time.sleep(0.4)
        assert alert_log.read_text() == '', 'CPU at the threshold must not trigger an alert.'
        assert capture_log.read_text() == '', 'CPU at the threshold must not send email.'

        with urllib.request.urlopen('http://127.0.0.1:7070/api/metrics', timeout=5) as response:
            high_body = response.read()
            assert response.status == 200
        assert high_body == expected_responses[1].encode(), 'Proxy did not return the backend response unchanged.'

        deadline = time.time() + 5
        while time.time() < deadline:
            if capture_log.stat().st_size and alert_log.stat().st_size:
                break
            time.sleep(0.05)

        high_cpu = json.loads(expected_responses[1])['cpu_usage']
        assert alert_log.read_text().splitlines() == [f'ALERT TRIGGERED: cpu={high_cpu}']
        messages = [json.loads(line) for line in capture_log.read_text().splitlines() if line]
        assert len(messages) == 1, 'Exactly one email should be sent for the high-CPU request.'
        message = messages[0]
        assert message['from'] == 'proxy@dashboard.local'
        assert message['to'] == ['alerts@dashboard.local']
        assert 'Subject: High CPU Alert' in message['data']
        assert f'CPU usage is at {high_cpu}%' in message['data']
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        kill_listeners(7070)


def test_dynamic_end_to_end_through_tunnel_and_smtp():
    rebuilt = pathlib.Path('/tmp/rebuilt_proxy_server')
    build = subprocess.run(
        ['go', 'build', '-o', str(rebuilt), 'main.go'], cwd=str(PROXY_DIR),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert build.returncode == 0, f'main.go does not build:\n{build.stdout}'

    kill_listeners(7070)
    kill_listeners(8080)
    kill_listeners(1025)

    rng = random.SystemRandom()
    values = []
    responses = []
    for _ in range(2):
        low = 85
        high = rng.randint(86, 99)
        token1 = os.urandom(10).hex()
        token2 = os.urandom(10).hex()
        responses.extend([
            f'{{ "memory_usage" : {rng.randint(1, 84)}, "cpu_usage" : {low}, "token" : "{token1}" }}',
            f'{{ "token" : "{token2}", "cpu_usage" : {high}, "memory_usage" : {rng.randint(1, 84)} }}'
        ])
        values.append((low, high))

    challenge = pathlib.Path('/tmp/verifier_responses.json')
    challenge.write_text(json.dumps(responses))
    pathlib.Path('/tmp/verifier_smtp.jsonl').write_text('')

    service_code = r'''
import asyncore, http.server, json, smtpd, threading, time
responses = json.load(open('/tmp/verifier_responses.json'))
class Handler(http.server.BaseHTTPRequestHandler):
    index = 0
    def do_GET(self):
        if self.path != '/api/metrics':
            self.send_response(404); self.end_headers(); return
        if Handler.index >= len(responses):
            self.send_response(500); self.end_headers(); return
        body = responses[Handler.index].encode(); Handler.index += 1
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *args): pass
class SMTP(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        if isinstance(data, bytes): data = data.decode('utf-8', 'replace')
        with open('/tmp/verifier_smtp.jsonl', 'a') as f:
            f.write(json.dumps({'from': mailfrom, 'to': rcpttos, 'data': data}) + '\n')
smtp = SMTP(('127.0.0.1', 1025), None)
threading.Thread(target=asyncore.loop, daemon=True).start()
http.server.HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
'''
    services = subprocess.Popen(['python3', '-c', service_code], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        wait_port(8080)
        wait_port(1025)
        assert services.poll() is None, 'Controlled backend/SMTP service exited.'

        run_behavioral_cases(PROXY_DIR / 'proxy_server', responses[0:2])
        run_behavioral_cases(rebuilt, responses[2:4])
        assert services.poll() is None, 'Controlled backend/SMTP service exited during testing.'
    finally:
        services.terminate()
        try:
            services.wait(timeout=2)
        except subprocess.TimeoutExpired:
            services.kill()
            services.wait()
PYTEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
