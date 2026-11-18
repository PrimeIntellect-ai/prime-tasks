#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import http.server
import os
import re
import signal
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import urllib.request

import pytest

PEN = '/home/user/bin/pen'
MONITOR = '/home/user/monitor.sh'


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def get_url(url, timeout=2):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.getcode(), response.read().decode('utf-8', errors='replace')


def processes_for_path(path):
    found = []
    expected = os.path.realpath(path)
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as handle:
                argv = [x.decode(errors='replace') for x in handle.read().split(b'\0') if x]
            exe = os.path.realpath(os.readlink(f'/proc/{entry}/exe'))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        if exe == expected or path in argv:
            found.append((int(entry), exe, argv))
    return found


def test_pen_c_fixed():
    """Keep the original source assertion."""
    pen_c_path = '/app/pen-0.34.1/pen.c'
    assert os.path.isfile(pen_c_path), f'Source file {pen_c_path} does not exist.'
    with open(pen_c_path, 'r') as handle:
        content = handle.read()
    assert 'usleep(200000);' not in content, (
        "The deliberate latency perturbation 'usleep(200000);' is still present in pen.c."
    )


def test_pen_installed_and_is_native_executable():
    """Keep the original installation checks and reject scripts/placeholders."""
    assert os.path.isfile(PEN), f'Compiled binary not found at {PEN}.'
    assert os.access(PEN, os.X_OK), f'Binary at {PEN} is not executable.'
    with open(PEN, 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', 'Installed pen must be a compiled ELF executable.'
    assert os.path.getsize(PEN) > 10000, 'Installed pen is implausibly small for the compiled program.'


def test_running_pen_is_installed_binary_with_round_robin_configuration():
    matches = processes_for_path(PEN)
    assert matches, 'The installed /home/user/bin/pen executable is not running.'
    configured = []
    for pid, exe, argv in matches:
        joined = ' '.join(argv)
        if '8080' in joined and all(str(port) in joined for port in (8001, 8002, 8003)):
            configured.append((pid, exe, argv))
    assert configured, 'Running pen is not configured for port 8080 and all three backends.'
    assert any('-r' in argv for _, _, argv in configured), (
        'Running pen must use its round-robin selection option (-r).'
    )
    assert any(exe == os.path.realpath(PEN) for _, exe, _ in configured), (
        'The process serving the configured load balancer is not the installed pen ELF.'
    )


def test_monitor_script_exists_and_has_required_configuration():
    """Keep original checks, then check the required target, loop and alert text."""
    assert os.path.isfile(MONITOR), f'Monitor script not found at {MONITOR}.'
    assert os.access(MONITOR, os.X_OK), f'Monitor script at {MONITOR} is not executable.'
    with open(MONITOR, 'r') as handle:
        text = handle.read()
    assert text.startswith('#!') and ('bash' in text.splitlines()[0]), 'monitor.sh must be a Bash script.'
    assert re.search(r'\bwhile\b[\s\S]*\b(do|true)\b', text), 'monitor.sh must contain an infinite loop.'
    assert 'curl' in text, 'monitor.sh must check the load balancer using curl.'
    assert '8080' in text, 'monitor.sh must check the load balancer on port 8080.'
    assert '/home/user/alerts.log' in text, 'monitor.sh must append to /home/user/alerts.log.'
    assert 'ALERT: LB latency high or unreachable' in text, 'Required alert message is missing.'


def test_monitor_is_running_in_background():
    assert processes_for_path(MONITOR), 'The /home/user/monitor.sh script is not running in the background.'


class MonitorHandler(http.server.BaseHTTPRequestHandler):
    delay = 0.0

    def do_GET(self):
        time.sleep(self.delay)
        body = b'OK\n'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


@contextlib.contextmanager
def monitor_http_server(delay):
    port = free_port()
    handler = type('ConfiguredMonitorHandler', (MonitorHandler,), {'delay': delay})
    server = socketserver.ThreadingTCPServer(('127.0.0.1', port), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield port
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def run_monitor_case(port, expect_alert):
    with open(MONITOR, 'r') as handle:
        source = handle.read()

    # Run the submitted logic unchanged except for redirecting its fixed endpoint
    # and log file to verifier-owned isolated resources.
    source = source.replace('/home/user/alerts.log', '/tmp/monitor-verifier-alerts.log')
    source = source.replace('127.0.0.1:8080', f'127.0.0.1:{port}')
    source = source.replace('localhost:8080', f'127.0.0.1:{port}')
    source = source.replace('0.0.0.0:8080', f'127.0.0.1:{port}')
    assert str(port) in source, 'Could not isolate the monitor endpoint for behavioral testing.'

    log = '/tmp/monitor-verifier-alerts.log'
    try:
        os.unlink(log)
    except FileNotFoundError:
        pass

    fd, script = tempfile.mkstemp(prefix='monitor-test-', suffix='.sh')
    os.close(fd)
    with open(script, 'w') as handle:
        handle.write(source)
    os.chmod(script, 0o700)
    proc = subprocess.Popen(
        ['/bin/bash', script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        deadline = time.time() + 4
        matched = False
        while time.time() < deadline:
            assert proc.poll() is None, 'monitor.sh exited instead of continuing its infinite loop.'
            if os.path.exists(log):
                with open(log, 'r') as handle:
                    lines = [line.rstrip('\n') for line in handle]
                matched = any(re.fullmatch(
                    r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ALERT: LB latency high or unreachable',
                    line
                ) for line in lines)
                if matched:
                    break
            time.sleep(0.1)
        if expect_alert:
            assert matched, 'monitor.sh did not append the required alert for a slow or failed request.'
        else:
            assert not os.path.exists(log) or os.path.getsize(log) == 0, (
                'monitor.sh incorrectly alerted for a successful request faster than 100ms.'
            )
    finally:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGTERM)
        with contextlib.suppress(subprocess.TimeoutExpired):
            proc.wait(timeout=2)
        with contextlib.suppress(FileNotFoundError):
            os.unlink(script)
        with contextlib.suppress(FileNotFoundError):
            os.unlink(log)


def test_monitor_behavior_fast_slow_and_failure():
    with monitor_http_server(0.0) as port:
        run_monitor_case(port, expect_alert=False)
    with monitor_http_server(0.25) as port:
        run_monitor_case(port, expect_alert=True)
    # Nothing listens on this reserved-and-released port, exercising curl failure.
    run_monitor_case(free_port(), expect_alert=True)


def test_backends_running():
    """Keep the original backend assertions and verify their simple OK response."""
    for port in [8001, 8002, 8003]:
        try:
            status, body = get_url(f'http://127.0.0.1:{port}', timeout=1)
            assert status == 200, f'Backend on port {port} returned status {status}.'
            assert 'OK' in body, f'Backend on port {port} does not serve the required OK response.'
        except Exception as exc:
            pytest.fail(f'Could not connect to backend server on port {port}: {exc}')


class LabelHandler(http.server.BaseHTTPRequestHandler):
    label = b''

    def do_GET(self):
        self.send_response(200)
        self.send_header('Connection', 'close')
        self.send_header('Content-Length', str(len(self.label)))
        self.end_headers()
        self.wfile.write(self.label)

    def log_message(self, *args):
        pass


def test_installed_pen_actually_round_robins_three_backends():
    """Execute the installed artifact against verifier-derived, distinct backends."""
    servers = []
    threads = []
    backend_ports = []
    proc = None
    try:
        for label in (b'backend-A', b'backend-B', b'backend-C'):
            handler = type('ConfiguredLabelHandler', (LabelHandler,), {'label': label})
            server = socketserver.ThreadingTCPServer(('127.0.0.1', 0), handler)
            servers.append(server)
            backend_ports.append(server.server_address[1])
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            threads.append(thread)

        listen_port = free_port()
        command = [PEN, '-f', '-r', str(listen_port)] + [f'127.0.0.1:{p}' for p in backend_ports]
        proc = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                start_new_session=True)
        deadline = time.time() + 5
        bodies = []
        while time.time() < deadline and not bodies:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors='replace')
                pytest.fail(f'Installed pen failed to start: {stderr}')
            try:
                _, body = get_url(f'http://127.0.0.1:{listen_port}', timeout=1)
                bodies.append(body)
            except Exception:
                time.sleep(0.05)
        assert bodies, 'Installed pen did not accept connections when executed by the verifier.'

        for _ in range(17):
            _, body = get_url(f'http://127.0.0.1:{listen_port}', timeout=1)
            bodies.append(body)
        assert set(bodies) == {'backend-A', 'backend-B', 'backend-C'}, (
            f'Installed pen did not distribute requests over all three backends: {set(bodies)}'
        )
    finally:
        if proc is not None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGTERM)
            with contextlib.suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=2)
        for server in servers:
            server.shutdown()
            server.server_close()
        for thread in threads:
            thread.join(timeout=2)


def test_load_balancer_throughput():
    """Keep the original load-balancer availability and throughput assertions."""
    try:
        status, _ = get_url('http://127.0.0.1:8080', timeout=2)
        assert status == 200, f'Load balancer returned status {status}.'
    except Exception as exc:
        pytest.fail(f'Could not connect to load balancer on port 8080: {exc}')

    num_requests = 1000
    start_time = time.time()
    success_count = 0
    for _ in range(num_requests):
        try:
            status, _ = get_url('http://127.0.0.1:8080', timeout=1)
            if status == 200:
                success_count += 1
        except Exception:
            pass
    duration = time.time() - start_time
    assert success_count > 0, 'All requests to the load balancer failed during benchmark.'
    rps = success_count / duration
    assert rps >= 500, f'Throughput is too low: {rps:.2f} RPS. Expected >= 500 RPS.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
