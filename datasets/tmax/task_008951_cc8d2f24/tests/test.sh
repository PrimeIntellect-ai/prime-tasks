#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import http.client
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time


def listening_inodes(ports):
    wanted = {f'{p:04X}' for p in ports}
    found = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == '0A':
                        if fields[1].rsplit(':', 1)[1].upper() in wanted:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def clear_test_ports():
    inodes = listening_inodes((8080, 8081, 8082, 9090))
    if not inodes:
        return
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
                    break
        except (FileNotFoundError, PermissionError):
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def wait_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f'127.0.0.1:{port} did not become ready')


def http_get(port, path='/verifier-derived-path'):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=4)
    try:
        conn.request('GET', path, headers={'Connection': 'close'})
        response = conn.getresponse()
        body = response.read().decode('utf-8')
        return response.status, dict(response.getheaders()), body
    finally:
        conn.close()


def stop_processes(processes):
    for process in reversed(processes):
        if process.poll() is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    for process in reversed(processes):
        if process.poll() is None:
            try:
                process.wait(max(0.05, deadline - time.time()))
            except subprocess.TimeoutExpired:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
    clear_test_ports()


def test_bashrc_timezone():
    bashrc_path = '/home/user/.bashrc'
    assert os.path.isfile(bashrc_path), f'{bashrc_path} is missing.'
    with open(bashrc_path, 'r') as f:
        content = f.read()
    assert ('APP_TIMEZONE="Asia/Tokyo"' in content or
            "APP_TIMEZONE='Asia/Tokyo'" in content or
            'APP_TIMEZONE=Asia/Tokyo' in content), \
        'APP_TIMEZONE setup is missing or incorrect in .bashrc.'


def test_go_files_exist():
    for gf in ('/home/user/backend.go', '/home/user/lb.go', '/home/user/forwarder.go'):
        assert os.path.isfile(gf), f'Go source file {gf} is missing.'


def test_run_system_script_executable():
    script_path = '/home/user/run_system.sh'
    assert os.path.isfile(script_path), f'Script {script_path} is missing.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {script_path} is not executable.'


def test_execution_and_log_verification():
    log_path = '/home/user/test_results.log'
    script_path = '/home/user/run_system.sh'
    clear_test_ports()
    try:
        if os.path.lexists(log_path):
            os.remove(log_path)

        process = subprocess.Popen(
            ['bash', script_path],
            cwd='/home/user',
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            returncode = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise AssertionError('run_system.sh did not finish within 120 seconds')
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        assert returncode == 0, f'run_system.sh exited with status {returncode}.'
        assert os.path.isfile(log_path), f'Log file {log_path} was not created after running the script.'

        with open(log_path, 'r') as f:
            log_content = f.read()

        count_8081 = len(re.findall(r'Backend responding from port 8081', log_content))
        count_8082 = len(re.findall(r'Backend responding from port 8082', log_content))
        assert count_8081 == 2, f'Expected exactly 2 responses from port 8081, found {count_8081}.'
        assert count_8082 == 2, f'Expected exactly 2 responses from port 8082, found {count_8082}.'

        time_headers = re.findall(r'X-Forwarded-Time:.*?\+09:00', log_content, re.IGNORECASE)
        assert len(time_headers) == 4, \
            f"Expected exactly 4 'X-Forwarded-Time' headers with '+09:00' timezone, found {len(time_headers)}."
        response_lines = re.findall(r'(?im)^HTTP/\d(?:\.\d)?\s+\d{3}\b', log_content)
        assert len(response_lines) == 4, f'Expected raw output from exactly 4 HTTP requests, found {len(response_lines)}.'
    finally:
        clear_test_ports()


def test_compiled_services_and_forwarding_behavior():
    clear_test_ports()
    processes = []
    with tempfile.TemporaryDirectory(prefix='service-verifier-') as build_dir:
        binaries = {}
        for name in ('backend', 'lb', 'forwarder'):
            output = os.path.join(build_dir, name)
            result = subprocess.run(
                ['go', 'build', '-o', output, f'/home/user/{name}.go'],
                cwd='/home/user', capture_output=True, text=True, timeout=120
            )
            assert result.returncode == 0, f'{name}.go failed to compile:\n{result.stderr}'
            binaries[name] = output

        try:
            for port in (8081, 8082):
                processes.append(subprocess.Popen(
                    [binaries['backend'], str(port)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                ))
                wait_port(port)
                status, _, body = http_get(port, f'/backend-check-{port}')
                assert status == 200
                assert body == f'Backend responding from port {port}'

            env = os.environ.copy()
            env['APP_TIMEZONE'] = 'Asia/Tokyo'
            processes.append(subprocess.Popen(
                [binaries['lb']], env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            ))
            wait_port(8080)

            direct_bodies = []
            for i in range(4):
                status, headers, body = http_get(8080, f'/lb-check-{i}')
                assert status == 200
                direct_bodies.append(body)
                forwarded_time = next((v for k, v in headers.items() if k.lower() == 'x-forwarded-time'), None)
                assert forwarded_time is not None, 'Load balancer omitted X-Forwarded-Time.'
                assert re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\+09:00', forwarded_time), \
                    f'Invalid RFC3339 Tokyo timestamp: {forwarded_time!r}'
                parsed = datetime.datetime.fromisoformat(forwarded_time)
                assert parsed.utcoffset() == datetime.timedelta(hours=9)
                now = datetime.datetime.now(datetime.timezone.utc)
                assert abs((parsed.astimezone(datetime.timezone.utc) - now).total_seconds()) < 120, \
                    'X-Forwarded-Time is not the current time.'

            expected_a = ['Backend responding from port 8081', 'Backend responding from port 8082'] * 2
            expected_b = ['Backend responding from port 8082', 'Backend responding from port 8081'] * 2
            assert direct_bodies in (expected_a, expected_b), f'Responses were not strict round-robin: {direct_bodies}'

            processes.append(subprocess.Popen(
                [binaries['forwarder']],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            ))
            wait_port(9090)
            forwarded_bodies = [http_get(9090, f'/forwarded-check-{i}')[2] for i in range(4)]
            assert forwarded_bodies in (expected_a, expected_b), \
                f'Requests through port 9090 were not forwarded to the round-robin proxy: {forwarded_bodies}'
        finally:
            stop_processes(processes)
            processes.clear()

        ready = threading.Event()
        stop = threading.Event()

        def echo_server():
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(('127.0.0.1', 8080))
            server.listen(8)
            server.settimeout(0.2)
            ready.set()
            try:
                while not stop.is_set():
                    try:
                        conn, _ = server.accept()
                    except socket.timeout:
                        continue
                    with conn:
                        data = b''
                        while len(data) < 37:
                            chunk = conn.recv(37 - len(data))
                            if not chunk:
                                break
                            data += chunk
                        if data:
                            conn.sendall(b'opaque-reply:' + data)
            finally:
                server.close()

        thread = threading.Thread(target=echo_server, daemon=True)
        thread.start()
        assert ready.wait(3), 'Could not start verifier TCP target.'
        try:
            forwarder = subprocess.Popen(
                [binaries['forwarder']],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            processes.append(forwarder)
            wait_port(9090)
            payload = b'\x00raw TCP verifier payload\xff0123456789'
            assert len(payload) == 37
            with socket.create_connection(('127.0.0.1', 9090), timeout=3) as client:
                client.sendall(payload)
                expected = b'opaque-reply:' + payload
                received = b''
                while len(received) < len(expected):
                    chunk = client.recv(len(expected) - len(received))
                    if not chunk:
                        break
                    received += chunk
            assert received == expected, 'Port 9090 did not transparently proxy arbitrary TCP bytes to port 8080.'
        finally:
            stop_processes(processes)
            stop.set()
            thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
