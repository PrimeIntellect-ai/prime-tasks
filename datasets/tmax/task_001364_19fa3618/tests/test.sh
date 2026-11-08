#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import threading
import time
import uuid
import pytest

HOME = '/home/user'


def stop_task_processes():
    for pattern in [
        '/home/user/metrics_server.py',
        '/home/user/supervisor.sh',
        '/home/user/capacity_planner',
    ]:
        subprocess.run(['pkill', '-f', pattern], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def expected_capacity():
    total = 0
    for root, dirs, files in os.walk('/home/user/data'):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total


def port_9090_is_closed():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.25)
    try:
        return s.connect_ex(('127.0.0.1', 9090)) != 0
    finally:
        s.close()


def test_ci_pipeline_exists_and_executable():
    path = '/home/user/ci_pipeline.sh'
    assert os.path.exists(path), f"CI pipeline script missing at {path}"
    assert os.access(path, os.X_OK), f"CI pipeline script at {path} is not executable"

    content = open(path, 'r').read()
    assert re.search(r'g\+\+[^\n]*-std=c\+\+17', content), \
        'CI pipeline does not compile with g++ -std=c++17.'
    assert '/home/user/capacity_planner.cpp' in content
    assert '/home/user/capacity_planner' in content
    assert '/home/user/supervisor.sh' in content


def test_supervisor_contains_fixes():
    path = '/home/user/supervisor.sh'
    assert os.path.exists(path), f"Supervisor script missing at {path}"
    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    has_port_wait = '9090' in content and ('nc' in content or '/dev/tcp' in content or 'sleep' in content)
    assert has_port_wait, "Supervisor script does not seem to wait for port 9090."

    has_restart_logic = 'while' in content or 'for' in content or 'until' in content
    assert has_restart_logic, "Supervisor script does not seem to contain restart logic for the C++ binary."


def test_pipeline_execution_and_output():
    stop_task_processes()
    token = uuid.uuid4().hex
    marker = f'/tmp/supervisor-invoked-{token}'
    backup = f'/tmp/supervisor-real-{token}.sh'
    supervisor = '/home/user/supervisor.sh'
    binary = '/home/user/capacity_planner'
    log = '/home/user/server.log'

    # Add data unknown when the submitted scripts were authored.
    challenge_dir = f'/home/user/data/verifier-{token}'
    os.makedirs(os.path.join(challenge_dir, 'nested'), exist_ok=True)
    with open(os.path.join(challenge_dir, 'nested', 'payload.bin'), 'wb') as f:
        f.write(os.urandom(17321))

    os.replace(supervisor, backup)
    with open(supervisor, 'w') as f:
        f.write('#!/bin/bash\n')
        f.write(f"printf invoked > '{marker}'\n")
        f.write(f"exec '{backup}' \"$@\"\n")
    os.chmod(supervisor, 0o755)

    try:
        if os.path.exists(binary):
            os.remove(binary)
        if os.path.exists(log):
            os.remove(log)

        try:
            proc = subprocess.run(
                ['/home/user/ci_pipeline.sh'],
                capture_output=True,
                text=True,
                timeout=20
            )
        except subprocess.TimeoutExpired:
            pytest.fail('CI pipeline script timed out after 20 seconds.')

        assert proc.returncode == 0, \
            f"Pipeline failed with exit code {proc.returncode}. Output: {proc.stdout}\nError: {proc.stderr}"
        assert 'PIPELINE SUCCESS' in proc.stdout, \
            "Pipeline script did not output 'PIPELINE SUCCESS'."
        assert os.path.exists(marker), \
            'The pipeline did not execute /home/user/supervisor.sh.'
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
            'The pipeline did not create an executable capacity_planner.'
        with open(binary, 'rb') as f:
            assert f.read(4) == b'\x7fELF', \
                'The generated capacity_planner is not a compiled ELF executable.'

        assert os.path.exists(log), f'{log} was not created.'
        with open(log, 'r') as f:
            log_content = f.read().strip()
        expected_log = f'CAPACITY:{expected_capacity()}'
        assert log_content.startswith(expected_log), \
            f"Expected log to start with '{expected_log}', found '{log_content}'"

        time.sleep(0.5)
        assert port_9090_is_closed(), \
            'The pipeline returned without terminating the metrics server.'
    finally:
        stop_task_processes()
        if os.path.exists(supervisor):
            os.remove(supervisor)
        if os.path.exists(backup):
            os.replace(backup, supervisor)
        if os.path.exists(marker):
            os.remove(marker)


def test_compiled_cpp_implementation_over_tcp_and_failure_status():
    stop_task_processes()
    source = '/home/user/capacity_planner.cpp'
    binary = '/home/user/capacity_planner'
    assert os.path.isfile(source), 'capacity_planner.cpp is missing.'

    compile_proc = subprocess.run(
        ['g++', '-std=c++17', source, '-o', binary],
        capture_output=True, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, \
        f'C++ source failed to compile: {compile_proc.stderr}'

    # Change the recursive input after compilation so a hard-coded answer fails.
    dynamic_dir = f'/home/user/data/dynamic-{uuid.uuid4().hex}/deep'
    os.makedirs(dynamic_dir, exist_ok=True)
    with open(os.path.join(dynamic_dir, 'new.bin'), 'wb') as f:
        f.write(os.urandom(8197))
    expected = f'CAPACITY:{expected_capacity()}\n'.encode()

    received = []
    ready = threading.Event()
    errors = []

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(('127.0.0.1', 9090))
                s.listen(1)
                ready.set()
                s.settimeout(5)
                conn, _ = s.accept()
                with conn:
                    conn.settimeout(2)
                    chunks = []
                    while True:
                        part = conn.recv(1024)
                        if not part:
                            break
                        chunks.append(part)
                    received.append(b''.join(chunks))
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(2), 'Mock metrics server did not start.'
    assert not errors, f'Mock server failed: {errors}'

    proc = subprocess.run([binary], capture_output=True, text=True, timeout=5)
    thread.join(5)
    assert proc.returncode == 0, \
        f'capacity_planner failed while a server was listening: {proc.stderr}'
    assert not thread.is_alive(), 'capacity_planner never connected to the TCP server.'
    assert not errors, f'Mock server failed: {errors}'
    assert received == [expected], \
        f'Expected exact TCP payload {expected!r}, received {received!r}'

    # With no listener, the required connection failure must be observable.
    assert port_9090_is_closed()
    failed = subprocess.run([binary], capture_output=True, text=True, timeout=5)
    assert failed.returncode != 0, \
        'capacity_planner returned success when its TCP connection failed.'


def test_supervisor_waits_and_restarts_no_more_than_three_attempts():
    stop_task_processes()
    token = uuid.uuid4().hex
    server_path = '/home/user/metrics_server.py'
    planner_path = '/home/user/capacity_planner'
    server_backup = f'/tmp/metrics-server-{token}'
    planner_backup = f'/tmp/capacity-planner-{token}'
    ready_file = f'/tmp/server-ready-{token}'
    attempts_file = f'/tmp/planner-attempts-{token}'

    os.replace(server_path, server_backup)
    had_planner = os.path.exists(planner_path)
    if had_planner:
        os.replace(planner_path, planner_backup)

    with open(server_path, 'w') as f:
        f.write("""#!/usr/bin/env python3
import socket, time
# Deliberately slow startup; remain alive after diagnostic connections.
time.sleep(1.3)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 9090))
s.listen(20)
open(%r, 'w').write(str(time.time()))
s.settimeout(20)
try:
    while True:
        c, _ = s.accept()
        c.close()
except Exception:
    pass
""" % ready_file)
    os.chmod(server_path, 0o755)

    with open(planner_path, 'w') as f:
        f.write("""#!/bin/bash
printf '%s\\n' "$(python3 -c 'import time; print(time.time())')" >> %s
exit 1
""" % attempts_file)
    os.chmod(planner_path, 0o755)

    proc = None
    try:
        proc = subprocess.Popen(
            ['/home/user/supervisor.sh'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True
        )
        deadline = time.time() + 10
        attempts = []
        while time.time() < deadline:
            if os.path.exists(attempts_file):
                with open(attempts_file) as f:
                    attempts = [float(x) for x in f.read().splitlines() if x.strip()]
                if len(attempts) >= 3:
                    break
            time.sleep(0.1)

        assert os.path.exists(ready_file), \
            'The supervisor did not wait for the metrics server to become ready.'
        assert len(attempts) >= 2, \
            'The supervisor did not restart the planner after a non-zero exit.'
        ready_time = float(open(ready_file).read())
        assert attempts[0] >= ready_time, \
            'The supervisor launched the planner before port 9090 was accepting connections.'

        time.sleep(1.2)
        with open(attempts_file) as f:
            attempts = [x for x in f.read().splitlines() if x.strip()]
        assert len(attempts) == 3, \
            f'Expected exactly 3 failed planner attempts, observed {len(attempts)}.'
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=2)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        stop_task_processes()
        if os.path.exists(server_path):
            os.remove(server_path)
        os.replace(server_backup, server_path)
        if os.path.exists(planner_path):
            os.remove(planner_path)
        if had_planner and os.path.exists(planner_backup):
            os.replace(planner_backup, planner_path)
        for path in [ready_file, attempts_file]:
            if os.path.exists(path):
                os.remove(path)


def test_server_log_contains_correct_capacity():
    log_path = '/home/user/server.log'
    assert os.path.exists(log_path), f"{log_path} was not created."

    with open(log_path, 'r') as f:
        log_content = f.read().strip()

    expected_log = f"CAPACITY:{expected_capacity()}"
    assert log_content.startswith(expected_log), \
        f"Expected log to start with '{expected_log}', found '{log_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
