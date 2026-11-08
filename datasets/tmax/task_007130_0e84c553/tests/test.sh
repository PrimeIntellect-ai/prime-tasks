#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import ssl
import subprocess
import time

import pytest

CERT = '/home/user/cert.pem'
KEY = '/home/user/key.pem'
SOURCE = '/home/user/monitor.go'
FETCH = '/home/user/fetch_metrics.sh'
REPORT = '/home/user/capacity_report.json'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, check=True, **kwargs)


def test_tls_certificates_exist():
    assert os.path.exists(CERT), '/home/user/cert.pem is missing'
    assert os.path.exists(KEY), '/home/user/key.pem is missing'


def test_capacity_worker_processes():
    try:
        output = subprocess.check_output(['ps', '-eo', 'args'], text=True)
        lines = output.strip().split('\n')
        workers = [
            line for line in lines
            if 'capacity-worker' in line
            and 'grep' not in line
            and 'pytest' not in line
            and 'monitor.go' not in line
        ]
        assert len(workers) >= 3, f'Expected at least 3 capacity-worker processes, found {len(workers)}'
    except subprocess.CalledProcessError:
        pytest.fail('Failed to execute ps command to check processes')


def test_go_server_listening():
    try:
        output = subprocess.check_output(['ss', '-tlnp'], text=True)
        assert ':8443 ' in output, 'Go server is not listening on port 8443'
    except subprocess.CalledProcessError:
        pytest.fail('Failed to run ss command')


def test_ssh_tunnel_listening():
    try:
        output = subprocess.check_output(['ss', '-tlnp'], text=True)
        assert ':9443 ' in output, 'SSH tunnel is not listening on port 9443'
    except subprocess.CalledProcessError:
        pytest.fail('Failed to run ss command')


def test_capacity_report_json():
    assert os.path.exists(REPORT), f'{REPORT} is missing'
    with open(REPORT) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{REPORT} does not contain valid JSON')
    assert isinstance(data, list), 'JSON root must be a list'
    assert len(data) == 3, f'Expected exactly 3 items in the report, found {len(data)}'
    for item in data:
        assert 'pid' in item, "Missing 'pid' key in report item"
        assert 'rss_kb' in item, "Missing 'rss_kb' key in report item"
        assert isinstance(item['pid'], int), "'pid' must be an integer"
        assert isinstance(item['rss_kb'], int), "'rss_kb' must be an integer"


def test_scripts_exist():
    assert os.path.exists(SOURCE), '/home/user/monitor.go is missing'
    assert os.path.exists(FETCH), '/home/user/fetch_metrics.sh is missing'


def worker_pids():
    result = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                argv = [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
            with open(f'/proc/{name}/comm') as f:
                comm = f.read().strip()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if (argv and argv[0] == 'capacity-worker') or comm == 'capacity-worker':
            result.append(int(name))
    return sorted(result)


def rss_kb(pid):
    with open(f'/proc/{pid}/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                return int(line.split()[1])
    raise AssertionError(f'No VmRSS value for worker PID {pid}')


def listener_rows(port):
    output = subprocess.check_output(['ss', '-H', '-ltnp'], text=True)
    rows = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 4 and fields[3].endswith(f':{port}'):
            rows.append(line)
    return rows


def listener_pids(rows):
    pids = set()
    for row in rows:
        pids.update(int(x) for x in re.findall(r'pid=(\d+)', row))
    return pids


def wait_for_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    raise AssertionError(f'Port {port} did not become available')


def https_get(port, path):
    context = ssl._create_unverified_context()
    conn = http.client.HTTPSConnection('127.0.0.1', port, timeout=8, context=context)
    conn.request('GET', path)
    response = conn.getresponse()
    body = response.read()
    headers = dict(response.getheaders())
    status = response.status
    conn.close()
    return status, headers, body


def peer_certificate(port):
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', port), timeout=8) as raw:
        with context.wrap_socket(raw, server_hostname='127.0.0.1') as tls:
            return tls.getpeercert(binary_form=True)


def parse_metrics(body):
    try:
        data = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError(f'/metrics did not return valid JSON: {exc}')
    assert isinstance(data, list), 'Metrics response root must be a list'
    assert len(data) == 3, f'Metrics response must contain exactly 3 workers, got {len(data)}'
    for item in data:
        assert isinstance(item, dict), 'Each metrics item must be an object'
        assert set(item) == {'pid', 'rss_kb'}, 'Metrics items must contain only pid and rss_kb'
        assert type(item['pid']) is int, 'pid must be an integer'
        assert type(item['rss_kb']) is int, 'rss_kb must be an integer'
    return data


def test_complete_secure_monitoring_setup():
    # Validate the certificate, curve, self-signature, and matching private key.
    assert os.path.isfile(CERT) and os.path.getsize(CERT) > 0
    assert os.path.isfile(KEY) and os.path.getsize(KEY) > 0
    cert_text = run(['openssl', 'x509', '-in', CERT, '-noout', '-text']).stdout
    assert 'id-ecPublicKey' in cert_text, 'Certificate key is not ECDSA'
    assert 'prime256v1' in cert_text or 'P-256' in cert_text, 'Certificate is not using P-256'
    subject = run(['openssl', 'x509', '-in', CERT, '-noout', '-subject']).stdout.split('=', 1)[-1].strip()
    issuer = run(['openssl', 'x509', '-in', CERT, '-noout', '-issuer']).stdout.split('=', 1)[-1].strip()
    assert subject == issuer, 'Certificate is not self-signed'
    run(['openssl', 'verify', '-CAfile', CERT, CERT])
    cert_pub = run(['openssl', 'x509', '-in', CERT, '-pubkey', '-noout']).stdout
    key_pub = run(['openssl', 'pkey', '-in', KEY, '-pubout']).stdout
    assert hashlib.sha256(cert_pub.encode()).digest() == hashlib.sha256(key_pub.encode()).digest(), \
        'Certificate and private key do not match'

    workers = worker_pids()
    assert len(workers) == 3, f'Expected exactly 3 genuinely named capacity-worker processes, found {workers}'

    # The original listener must be bound strictly to the requested loopback address.
    rows8443 = listener_rows(8443)
    assert rows8443, 'Nothing is listening on port 8443'
    assert all(row.split()[3] == '127.0.0.1:8443' for row in rows8443), \
        f'Port 8443 is not bound strictly to 127.0.0.1: {rows8443}'
    old_pids = listener_pids(rows8443)
    assert old_pids, 'Could not identify the process listening on port 8443'

    # Compile and actually execute the submitted Go artifact, replacing only the
    # submitted server listener so all following behavioral checks exercise it.
    assert os.path.isfile(SOURCE) and os.path.getsize(SOURCE) > 0
    go = shutil.which('go', path='/usr/local/go/bin:/usr/bin:/bin')
    assert go, 'Go compiler is unavailable'
    built = '/tmp/submitted-monitor'
    subprocess.run([go, 'build', '-o', built, SOURCE], cwd='/home/user', check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90)
    for pid in old_pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_rows(8443) and time.time() < deadline:
        time.sleep(0.1)
    if listener_rows(8443):
        for pid in listener_pids(listener_rows(8443)):
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass
        time.sleep(0.3)
    subprocess.Popen([built], cwd='/home/user', stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    wait_for_port(8443)
    rows8443 = listener_rows(8443)
    assert rows8443 and all(row.split()[3] == '127.0.0.1:8443' for row in rows8443), \
        'The submitted Go program did not listen strictly on 127.0.0.1:8443'

    # Port 9443 must be owned by an SSH client configured for the required forwarding.
    rows9443 = listener_rows(9443)
    assert rows9443, 'Nothing is listening on port 9443'
    ssh_pids = listener_pids(rows9443)
    assert ssh_pids, 'Could not identify the SSH tunnel process'
    found_tunnel = False
    for pid in ssh_pids:
        try:
            exe = os.path.basename(os.readlink(f'/proc/{pid}/exe'))
            argv = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
        except (FileNotFoundError, PermissionError):
            continue
        compact = argv.replace(' ', '')
        if exe == 'ssh' and '9443:127.0.0.1:8443' in compact and 'localhost' in argv:
            found_tunnel = True
    assert found_tunnel, 'Port 9443 is not the required SSH local-forwarding tunnel'

    expected_cert = ssl.PEM_cert_to_DER_cert(open(CERT).read())
    assert peer_certificate(8443) == expected_cert, 'Direct server presents a different certificate'
    assert peer_certificate(9443) == expected_cert, 'Tunnel does not reach the submitted TLS server'

    direct_status, direct_headers, direct_body = https_get(8443, '/metrics')
    tunnel_status, tunnel_headers, tunnel_body = https_get(9443, '/metrics')
    assert direct_status == 200 and tunnel_status == 200, '/metrics must return HTTP 200 directly and through SSH'
    assert 'application/json' in direct_headers.get('Content-Type', ''), '/metrics must have a JSON content type'
    direct_data = parse_metrics(direct_body)
    tunnel_data = parse_metrics(tunnel_body)
    assert direct_data == tunnel_data, 'Direct and tunneled metrics responses differ'

    actual = {pid: rss_kb(pid) for pid in workers}
    reported = {item['pid']: item['rss_kb'] for item in tunnel_data}
    assert set(reported) == set(workers), f'Reported PIDs {sorted(reported)} do not match workers {workers}'
    assert reported == actual, f'Reported RSS values {reported} do not match live process RSS {actual}'

    for path in ('/', '/not-a-metrics-endpoint'):
        status, _, _ = https_get(8443, path)
        assert status == 404, f'Unexpected endpoint {path} returned HTTP {status}, expected 404'

    # Inspect and execute the submitted collection script, then ensure it saved
    # the exact response obtained through the tunnel.
    assert os.path.isfile(FETCH) and os.path.getsize(FETCH) > 0
    script = open(FETCH).read()
    assert re.search(r'\bcurl\b', script), 'fetch_metrics.sh does not use curl'
    assert '9443' in script and '/metrics' in script, 'fetch_metrics.sh does not target tunneled /metrics'
    assert re.search(r'(^|\s)(-k|--insecure)(\s|$)', script), 'fetch_metrics.sh does not ignore self-signed TLS warnings'
    assert '/home/user/capacity_report.json' in script, 'fetch_metrics.sh does not write the required report path'
    try:
        os.remove(REPORT)
    except FileNotFoundError:
        pass
    subprocess.run(['/bin/bash', FETCH], cwd='/home/user', check=True, timeout=20,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert os.path.isfile(REPORT), 'Executing fetch_metrics.sh did not create the report'
    with open(REPORT, 'rb') as f:
        report_body = f.read()
    status, _, current_tunnel_body = https_get(9443, '/metrics')
    assert status == 200
    assert report_body == current_tunnel_body, 'Report is not the exact JSON response returned through port 9443'
    report_data = parse_metrics(report_body)
    current_workers = worker_pids()
    assert current_workers == workers, 'Worker process set changed during verification'
    current_actual = {pid: rss_kb(pid) for pid in current_workers}
    assert {x['pid']: x['rss_kb'] for x in report_data} == current_actual, \
        'capacity_report.json does not contain live worker PIDs and RSS values'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
