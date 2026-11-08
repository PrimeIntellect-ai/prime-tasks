#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import re
import stat
import subprocess
import time
import urllib.request
import urllib.error
import importlib.util
from html.parser import HTMLParser
from pathlib import Path
import pytest

HOME = Path('/home/user')
EXCLUDED_ARTIFACTS = {
    Path('/home/user/scan_data.json'),
    Path('/home/user/vulnerable.csv'),
    Path('/home/user/xss_payload.txt'),
    Path('/home/user/webapp/app.py'),
    Path('/home/user/ssh_configs/sshd_config'),
    Path('/home/user/ssh_configs/sshd_config_hardened'),
}


def script_command(path):
    try:
        first = path.open('rb').readline(256).decode('utf-8', errors='ignore').lower()
    except OSError:
        return None
    suffix = path.suffix.lower()
    if suffix == '.py' or (first.startswith('#!') and 'python' in first):
        return ['python3', str(path)]
    if suffix in {'.sh', '.bash'} or (first.startswith('#!') and ('/sh' in first or 'bash' in first)):
        return ['bash', str(path)]
    if path.stat().st_mode & stat.S_IXUSR:
        return [str(path)]
    return None


def submitted_scripts():
    scripts = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path in EXCLUDED_ARTIFACTS or '__pycache__' in path.parts:
            continue
        command = script_command(path)
        if command is not None:
            scripts.append((path, command))
    return scripts


def save_file(path):
    return path.exists(), path.read_bytes() if path.exists() else b''


def restore_file(path, saved):
    existed, data = saved
    if existed:
        path.write_bytes(data)
    elif path.exists():
        path.unlink()


def run_script(command):
    return subprocess.run(
        command,
        cwd=str(Path(command[-1]).parent),
        env={**os.environ, 'HOME': '/home/user'},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=8,
    ).returncode == 0


def expected_vulnerable_rows(scan_data):
    rows = []
    for svc in scan_data:
        unencrypted = svc.get('encryption') == 'none' and svc.get('port') != 80
        cves = svc.get('cve_count', 0) > 0
        if unencrypted and cves:
            reason = 'Critical'
        elif unencrypted:
            reason = 'Unencrypted'
        elif cves:
            reason = 'CVEs Found'
        else:
            continue
        rows.append({'IP': svc['ip'], 'Port': str(svc['port']), 'Service': svc['service'], 'Reason': reason})
    rows.sort(key=lambda row: int(row['Port']))
    return rows


def read_vulnerable_csv(path):
    with path.open(newline='') as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        return reader.fieldnames, rows


def test_objective1_vulnerable_csv():
    csv_path = Path('/home/user/vulnerable.csv')
    json_path = Path('/home/user/scan_data.json')
    assert csv_path.exists(), f'File not found: {csv_path}'
    assert json_path.exists(), f'File not found: {json_path}'

    with json_path.open() as handle:
        scan_data = json.load(handle)
    expected_rows = expected_vulnerable_rows(scan_data)
    fieldnames, actual_rows = read_vulnerable_csv(csv_path)

    assert fieldnames == ['IP', 'Port', 'Service', 'Reason'], 'CSV headers do not match the required format exactly.'
    assert len(actual_rows) == len(expected_rows), 'The number of vulnerable services in the CSV is incorrect.'
    for actual, expected in zip(actual_rows, expected_rows):
        assert actual == expected, f'Row mismatch. Expected {expected}, got {actual}'


def test_objective1_processing_script_executes_on_new_data():
    scripts = submitted_scripts()
    assert scripts, 'No processing or hardening script was written under /home/user.'

    json_path = Path('/home/user/scan_data.json')
    csv_path = Path('/home/user/vulnerable.csv')
    saved_json = save_file(json_path)
    saved_csv = save_file(csv_path)
    fixture = [
        {'ip': '10.20.30.1', 'port': 80, 'service': 'allowed-http', 'encryption': 'none', 'cve_count': 0},
        {'ip': '10.20.30.2', 'port': 31337, 'service': 'plain', 'encryption': 'none', 'cve_count': 0},
        {'ip': '10.20.30.3', 'port': 7, 'service': 'cve-only', 'encryption': 'strong', 'cve_count': 4},
        {'ip': '10.20.30.4', 'port': 444, 'service': 'both', 'encryption': 'none', 'cve_count': 2},
        {'ip': '10.20.30.5', 'port': 9000, 'service': 'safe', 'encryption': 'strong', 'cve_count': 0},
    ]
    expected = expected_vulnerable_rows(fixture)
    succeeded = False
    try:
        for _, command in scripts:
            json_path.write_text(json.dumps(fixture))
            if csv_path.exists():
                csv_path.unlink()
            try:
                completed = run_script(command)
            except (subprocess.TimeoutExpired, OSError):
                completed = False
            if not completed or not csv_path.exists():
                continue
            try:
                fields, rows = read_vulnerable_csv(csv_path)
            except Exception:
                continue
            if fields == ['IP', 'Port', 'Service', 'Reason'] and rows == expected:
                succeeded = True
                break
    finally:
        restore_file(json_path, saved_json)
        restore_file(csv_path, saved_csv)
    assert succeeded, 'No submitted script correctly regenerated vulnerable.csv from changed scan data.'


class PayloadParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.script_text = []
        self.autorun_handler = False

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        values = {str(k).lower(): (v or '') for k, v in attrs}
        if tag == 'script':
            self.in_script = True
        if tag == 'img' and values.get('src') and re.search(r'alert\s*\(\s*document\.domain\s*\)', values.get('onerror', ''), re.I):
            self.autorun_handler = True
        if tag in {'svg', 'body'} and re.search(r'alert\s*\(\s*document\.domain\s*\)', values.get('onload', ''), re.I):
            self.autorun_handler = True

    def handle_endtag(self, tag):
        if tag.lower() == 'script':
            self.in_script = False

    def handle_data(self, data):
        if self.in_script:
            self.script_text.append(data)


def test_objective2_xss_payload():
    payload_path = '/home/user/xss_payload.txt'
    assert os.path.exists(payload_path), f'File not found: {payload_path}'
    with open(payload_path) as handle:
        content = handle.read().strip()

    assert 'alert(document.domain)' in content.replace(' ', ''), 'The payload does not contain the required alert function.'
    is_script = re.search(r'<script\b[^>]*>.*alert\(document\.domain\).*</script>', content, re.IGNORECASE | re.DOTALL)
    is_event = re.search(r'<[^>]+on\w+\s*=\s*["\']?.*alert\(document\.domain\)["\']?[^>]*>', content, re.IGNORECASE | re.DOTALL)
    assert is_script or is_event, 'The payload is not a valid XSS vector (missing script tags or event handlers).'

    parser = PayloadParser()
    parser.feed(content)
    script_executes = bool(re.search(r'alert\s*\(\s*document\.domain\s*\)', ''.join(parser.script_text), re.I))
    assert script_executes or parser.autorun_handler, 'The event attribute is not a browser event that automatically executes the required alert on page load.'


def fetch_response(url, method='GET'):
    request = urllib.request.Request(url, method=method)
    try:
        return urllib.request.urlopen(request, timeout=2)
    except urllib.error.HTTPError as error:
        return error


def test_objective3_csp_headers():
    app_path = '/home/user/webapp/app.py'
    assert os.path.exists(app_path), f'File not found: {app_path}'
    proc = subprocess.Popen(['python3', app_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    expected_policy = "default-src 'self'; script-src 'none';"
    try:
        deadline = time.time() + 5
        while True:
            if proc.poll() is not None:
                pytest.fail('The Flask application exited before accepting requests.')
            try:
                response = fetch_response('http://127.0.0.1:8080/greet')
                break
            except urllib.error.URLError as error:
                if time.time() >= deadline:
                    pytest.fail(f'Failed to connect to the Flask application: {error}')
                time.sleep(0.1)

        csp_header = response.headers.get('Content-Security-Policy')
        assert csp_header is not None, 'Content-Security-Policy header is missing from the response.'
        assert expected_policy in csp_header, f'CSP header value is incorrect. Expected to find: {expected_policy}'
        assert csp_header == expected_policy, 'The CSP header must exactly match the required policy.'

        checks = [
            ('http://127.0.0.1:8080/greet?name=RouteCheck', 'GET', 200),
            ('http://127.0.0.1:8080/does-not-exist', 'GET', 404),
            ('http://127.0.0.1:8080/greet', 'POST', 405),
            ('http://127.0.0.1:8080/static/missing-file', 'GET', 404),
        ]
        for url, method, status in checks:
            checked = fetch_response(url, method)
            assert checked.status == status
            assert checked.headers.get('Content-Security-Policy') == expected_policy, f'CSP is missing or incorrect for {method} {url}.'
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_objective3_routing_logic_preserved():
    app_path = '/home/user/webapp/app.py'
    spec = importlib.util.spec_from_file_location('submitted_webapp', app_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    app = module.app

    rules = {(rule.rule, tuple(sorted(rule.methods - {'HEAD', 'OPTIONS'}))) for rule in app.url_map.iter_rules()}
    assert rules == {('/static/<path:filename>', ('GET',)), ('/greet', ('GET',))}, 'The original Flask routing logic was changed.'

    client = app.test_client()
    default = client.get('/greet')
    named = client.get('/greet', query_string={'name': 'Alice & Bob'})
    missing = client.get('/not-a-route')
    wrong_method = client.post('/greet')
    expected_policy = "default-src 'self'; script-src 'none';"

    assert default.status_code == 200
    assert default.get_data(as_text=True) == '<html><body><h1>Hello, Guest!</h1></body></html>'
    assert named.status_code == 200
    assert named.get_data(as_text=True) == '<html><body><h1>Hello, Alice & Bob!</h1></body></html>'
    assert missing.status_code == 404
    assert wrong_method.status_code == 405
    for response in (default, named, missing, wrong_method):
        assert response.headers.get('Content-Security-Policy') == expected_policy, 'Every Flask response must carry the exact CSP policy.'


def parse_active_config(path):
    entries = []
    with path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                entries.append((parts[0], ' '.join(parts[1:])))
    return entries


def test_objective4_ssh_hardening():
    hardened_path = Path('/home/user/ssh_configs/sshd_config_hardened')
    assert hardened_path.exists(), f'File not found: {hardened_path}'
    config = dict(parse_active_config(hardened_path))

    assert config.get('PermitRootLogin') == 'no', "PermitRootLogin is not set to 'no'."
    assert config.get('PasswordAuthentication') == 'no', "PasswordAuthentication is not set to 'no'."
    assert config.get('Ciphers') == 'chacha20-poly1305@openssh.com,aes256-gcm@openssh.com', 'Ciphers line is incorrect or missing.'
    assert config.get('Port') == '22', "Existing configuration 'Port 22' was not preserved."
    assert config.get('MaxAuthTries') == '6', "Existing configuration 'MaxAuthTries 6' was not preserved."
    assert config.get('X11Forwarding') == 'no', "Existing configuration 'X11Forwarding no' was not preserved."


def test_objective4_hardening_script_executes_and_preserves_config():
    scripts = submitted_scripts()
    assert scripts, 'No processing or hardening script was written under /home/user.'

    source = Path('/home/user/ssh_configs/sshd_config')
    output = Path('/home/user/ssh_configs/sshd_config_hardened')
    saved_source = save_file(source)
    saved_output = save_file(output)
    fixture = '''# dynamic verifier fixture
Port 2222
PermitRootLogin prohibit-password
MaxAuthTries 3
PasswordAuthentication yes
X11Forwarding yes
AllowUsers alice bob
ClientAliveInterval 47
Ciphers aes128-ctr
'''
    required = {
        'PermitRootLogin': 'no',
        'PasswordAuthentication': 'no',
        'Ciphers': 'chacha20-poly1305@openssh.com,aes256-gcm@openssh.com',
        'Port': '2222',
        'MaxAuthTries': '3',
        'X11Forwarding': 'yes',
        'AllowUsers': 'alice bob',
        'ClientAliveInterval': '47',
    }
    succeeded = False
    try:
        for _, command in scripts:
            source.write_text(fixture)
            if output.exists():
                output.unlink()
            try:
                completed = run_script(command)
            except (subprocess.TimeoutExpired, OSError):
                completed = False
            if not completed or not output.exists():
                continue
            try:
                entries = parse_active_config(output)
            except Exception:
                continue
            config = dict(entries)
            target_values = {
                key: [value for entry_key, value in entries if entry_key.lower() == key.lower()]
                for key in ('PermitRootLogin', 'PasswordAuthentication', 'Ciphers')
            }
            targets_safe = (
                target_values['PermitRootLogin'] and all(v == 'no' for v in target_values['PermitRootLogin']) and
                target_values['PasswordAuthentication'] and all(v == 'no' for v in target_values['PasswordAuthentication']) and
                target_values['Ciphers'] and all(v == required['Ciphers'] for v in target_values['Ciphers'])
            )
            if targets_safe and all(config.get(key) == value for key, value in required.items()):
                succeeded = True
                break
    finally:
        restore_file(source, saved_source)
        restore_file(output, saved_output)
    assert succeeded, 'No submitted script correctly hardened a changed SSH configuration while preserving non-conflicting settings.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
