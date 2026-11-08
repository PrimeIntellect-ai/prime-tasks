#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import signal
import socket
import subprocess
import time
from pathlib import Path

SCRIPT = Path('/home/user/audit_server.sh')
RESULTS = Path('/home/user/audit_results.txt')
SERVER = Path('/home/user/legacy_server')
REAL_SERVER = Path('/tmp/verifier_legacy_server.real')
CURL = Path('/usr/bin/curl')
REAL_CURL = Path('/tmp/verifier_curl.real')
SERVER_LOG = Path('/tmp/verifier_server.log')
CURL_LOG = Path('/tmp/verifier_curl.log')
REQUEST_LOG = Path('/tmp/verifier_request.log')

ENDPOINT = '/api/v2/legacy_admin_auth'
CSP = "CSP: Content-Security-Policy: default-src 'self'; script-src 'self';"
EXPECTED = (
    'Endpoint: /api/v2/legacy_admin_auth\n'
    'Cookie: legacy_token\n'
    "CSP: Content-Security-Policy: default-src 'self'; script-src 'self';"
)


def read_results():
    assert RESULTS.exists(), f'Missing required results file: {RESULTS}'
    assert RESULTS.is_file(), f'{RESULTS} is not a file.'
    return RESULTS.read_text().strip()


def port_is_open():
    sock = socket.socket()
    sock.settimeout(0.15)
    try:
        return sock.connect_ex(('127.0.0.1', 8888)) == 0
    finally:
        sock.close()


def wait_for_closed():
    for _ in range(30):
        if not port_is_open():
            return True
        time.sleep(0.1)
    return False


def kill_marked_processes():
    markers = (str(REAL_SERVER), str(SERVER))
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            if any(marker in cmdline for marker in markers):
                os.kill(int(entry.name), signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


def install_curl_probe():
    os.rename(CURL, REAL_CURL)
    CURL.write_text(f'''#!/bin/bash
printf '%s\\t%s\\n' "$(date +%s%N)" "$*" >> {CURL_LOG}
exec {REAL_CURL} "$@"
''')
    CURL.chmod(0o755)


def restore_curl():
    try:
        if CURL.exists() or CURL.is_symlink():
            CURL.unlink()
    finally:
        if REAL_CURL.exists():
            os.rename(REAL_CURL, CURL)


def install_real_server_probe():
    os.rename(SERVER, REAL_SERVER)
    SERVER.write_text(f'''#!/bin/bash
printf '%s\\t%s\\n' "$(date +%s%N)" "$(ulimit -v)" >> {SERVER_LOG}
exec {REAL_SERVER} "$@"
''')
    SERVER.chmod(0o755)


def install_dynamic_server(cookie_name):
    os.rename(SERVER, REAL_SERVER)
    SERVER.write_text(f'''#!/usr/bin/python3
import resource
import signal
import socket
import time

with open({str(SERVER_LOG)!r}, 'a') as log:
    log.write(str(time.time_ns()) + '\\t' + str(resource.getrlimit(resource.RLIMIT_AS)[0] // 1024) + '\\n')

sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('0.0.0.0', 8888))
sock.listen(5)
while True:
    conn, _ = sock.accept()
    data = b''
    while b'\\r\\n\\r\\n' not in data and len(data) < 16384:
        part = conn.recv(4096)
        if not part:
            break
        data += part
    first = data.split(b'\\r\\n', 1)[0].decode(errors='replace')
    with open({str(REQUEST_LOG)!r}, 'a') as log:
        log.write(first + '\\n')
    if first.startswith('GET {ENDPOINT} '):
        response = "HTTP/1.1 200 OK\\r\\nSet-Cookie: {cookie_name}=dynamic-value; Path=/\\r\\nContent-Type: text/plain\\r\\nContent-Length: 2\\r\\n\\r\\nOK"
    else:
        response = "HTTP/1.1 404 Not Found\\r\\nContent-Length: 0\\r\\n\\r\\n"
    conn.sendall(response.encode())
    conn.close()
''')
    SERVER.chmod(0o755)


def restore_server():
    kill_marked_processes()
    wait_for_closed()
    try:
        if SERVER.exists() or SERVER.is_symlink():
            SERVER.unlink()
    finally:
        if REAL_SERVER.exists():
            os.rename(REAL_SERVER, SERVER)


def clear_logs():
    for path in (SERVER_LOG, CURL_LOG, REQUEST_LOG, RESULTS):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_script():
    assert not port_is_open(), 'Port 8888 was already occupied before the audit script ran.'
    completed = subprocess.run(
        [str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=7,
        env=os.environ.copy(),
    )
    assert completed.returncode == 0, (
        f'Audit script failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert wait_for_closed(), 'The audit script did not terminate the background server process.'


def assert_probe_evidence():
    assert SERVER_LOG.exists(), 'The audit script did not start /home/user/legacy_server.'
    server_lines = [line for line in SERVER_LOG.read_text().splitlines() if line.strip()]
    assert server_lines, 'No server execution was recorded.'
    start_ns, limit_kb = server_lines[-1].split('\t', 1)
    assert int(limit_kb) == 50000, (
        f'The server did not inherit the required 50,000 KB virtual-memory limit; got {limit_kb} KB.'
    )

    assert CURL_LOG.exists(), 'The audit script did not invoke curl.'
    curl_lines = [line for line in CURL_LOG.read_text().splitlines() if line.strip()]
    assert curl_lines, 'No curl invocation was recorded.'
    curl_ns, curl_args = curl_lines[-1].split('\t', 1)
    assert ENDPOINT in curl_args, f'curl was not used to request the hidden endpoint: {curl_args}'
    assert int(curl_ns) - int(start_ns) <= 2_500_000_000, (
        'The script waited more than 2 seconds before attempting the HTTP request.'
    )


def test_audit_workflow():
    assert SCRIPT.exists(), f'Missing required script: {SCRIPT}'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable.'

    script_content = SCRIPT.read_text()
    assert script_content.startswith('#!') and 'bash' in script_content.splitlines()[0], (
        'The audit script must use Bash.'
    )
    assert 'ulimit -v 50000' in script_content, (
        f"The script {SCRIPT} must set a strict virtual memory limit using 'ulimit -v 50000'."
    )

    install_curl_probe()
    try:
        # Execute against the supplied binary and retain the original exact-content assertion.
        clear_logs()
        install_real_server_probe()
        try:
            run_script()
            assert_probe_evidence()
            actual = read_results()
            assert actual == EXPECTED, (
                f'Content of {RESULTS} does not match expected output.\n'
                f'Expected:\n{EXPECTED}\n\nActual:\n{actual}'
            )
        finally:
            restore_server()

        # Vary the server-provided cookie to ensure the script extracts it from Set-Cookie
        # rather than merely writing the known answer.
        cookie = f'audit_probe_{os.getpid()}_{time.time_ns()}'
        clear_logs()
        install_dynamic_server(cookie)
        try:
            run_script()
            assert_probe_evidence()
            requests = REQUEST_LOG.read_text().splitlines() if REQUEST_LOG.exists() else []
            assert any(line.startswith(f'GET {ENDPOINT} ') for line in requests), (
                'The running server did not receive a GET for the hidden endpoint.'
            )
            expected_dynamic = f'Endpoint: {ENDPOINT}\nCookie: {cookie}\n{CSP}'
            assert read_results() == expected_dynamic, (
                'The report did not use the cookie name supplied dynamically by Set-Cookie.'
            )
        finally:
            restore_server()

        # Leave the required report in its specified final form.
        clear_logs()
        install_real_server_probe()
        try:
            run_script()
            assert_probe_evidence()
            assert read_results() == EXPECTED
        finally:
            restore_server()
    finally:
        restore_curl()
        kill_marked_processes()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
