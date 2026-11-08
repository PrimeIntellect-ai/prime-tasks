#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import pathlib
import shlex
import signal
import socket
import stat
import subprocess
import time
import uuid

import pytest

HOME = pathlib.Path('/home/user')
SCRIPTS = [
    HOME / 'analyze.sh',
    HOME / 'supervisor.sh',
    HOME / 'tunnel.sh',
    HOME / 'pipeline.sh',
]


def run_user(command, timeout=15):
    return subprocess.run(
        ['runuser', '--user', 'user', '--'] + list(command),
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def process_comm(pid):
    try:
        with open(f'/proc/{pid}/comm', 'r') as f:
            return f.read().strip()
    except (FileNotFoundError, ProcessLookupError):
        return None


def stop_socat_from_pidfile():
    pidfile = HOME / 'tunnel.pid'
    if not pidfile.is_file():
        return
    value = pidfile.read_text().strip()
    if not value.isdigit():
        return
    pid = int(value)
    if process_comm(pid) == 'socat':
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        for _ in range(30):
            if process_comm(pid) != 'socat':
                break
            time.sleep(0.1)


@contextlib.contextmanager
def mocked_agent(body):
    path = HOME / 'deploy_agent.sh'
    original = path.read_bytes()
    original_mode = stat.S_IMODE(path.stat().st_mode)
    try:
        path.write_text('#!/bin/bash\n' + body)
        os.chown(path, 1000, 1000)
        os.chmod(path, 0o755)
        yield
    finally:
        path.write_bytes(original)
        os.chown(path, 1000, 1000)
        os.chmod(path, original_mode)


def test_scripts_exist_and_executable():
    for script in SCRIPTS:
        assert script.is_file(), f'Script {script} is missing.'
        assert script.stat().st_mode & stat.S_IXUSR, f'Script {script} is not executable.'


def test_analyze_script_behavior():
    logs = HOME / 'logs'
    existing = {p.name: p.read_bytes() for p in logs.glob('deploy_*.log')}
    token = uuid.uuid4().hex[:8]
    generated = {
        'deploy_a.log': (
            f'Connecting to host zeta-{token} [172.20.1.9] port 22.\n'
            'Connection closed by authenticating user deploy\n'
        ),
        'deploy_b.log': (
            f'Connecting to host alpha-{token} [172.20.1.3] port 22.\n'
            'Connection closed by authenticating user deploy\n'
        ),
        'deploy_c.log': (
            f'Connecting to host middle-{token} [172.20.1.5] port 22.\n'
            'Authentication succeeded (publickey).\n'
        ),
        'deploy_d.log': (
            f'Connecting to host decoy-{token} [172.20.1.7] port 22.\n'
            'Connection closed by authenticating user deploy later\n'
        ),
    }
    try:
        for p in logs.glob('deploy_*.log'):
            p.unlink()
        for name, content in generated.items():
            (logs / name).write_text(content)
        result = run_user(['./analyze.sh'])
        assert result.returncode == 0, result.stderr
        assert read_nonempty_lines(HOME / 'failed_servers.txt') == [
            f'alpha-{token},172.20.1.3',
            f'zeta-{token},172.20.1.9',
        ]
    finally:
        for p in logs.glob('deploy_*.log'):
            p.unlink()
        for name, content in existing.items():
            (logs / name).write_bytes(content)


def test_supervisor_stops_after_third_crash():
    counter = f'/tmp/supervisor_counter_{uuid.uuid4().hex}'
    body = (
        f'counter={shlex.quote(counter)}\n'
        'n=0\n'
        '[ -f "$counter" ] && n=$(cat "$counter")\n'
        'n=$((n + 1))\n'
        'echo "$n" > "$counter"\n'
        'exit 1\n'
    )
    (HOME / 'supervisor.log').write_text('')
    try:
        with mocked_agent(body):
            result = run_user(['./supervisor.sh'])
        assert result.returncode == 1, result.stderr
        assert pathlib.Path(counter).read_text().strip() == '3'
        assert read_nonempty_lines(HOME / 'supervisor.log') == [
            '[WARN] Agent crashed, restarting',
            '[WARN] Agent crashed, restarting',
            '[WARN] Agent crashed, restarting',
            '[ERROR] Max retries reached',
        ]
    finally:
        pathlib.Path(counter).unlink(missing_ok=True)


def test_supervisor_success_behavior():
    (HOME / 'supervisor.log').write_text('')
    with mocked_agent('exit 0\n'):
        result = run_user(['./supervisor.sh'])
    assert result.returncode == 0, result.stderr
    assert read_nonempty_lines(HOME / 'supervisor.log') == ['[INFO] Agent succeeded']


def test_tunnel_script_forwards_traffic_and_records_real_pid():
    stop_socat_from_pidfile()
    token = uuid.uuid4().hex.encode()
    server_code = (
        'import socket\n'
        's=socket.socket()\n'
        's.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)\n'
        's.bind(("127.0.0.1",9090))\n'
        's.listen(1)\n'
        'c,_=s.accept()\n'
        'd=c.recv(4096)\n'
        'c.sendall(d)\n'
        'c.close()\n'
        's.close()\n'
    )
    backend = subprocess.Popen(['python3', '-c', server_code])
    pid = None
    try:
        time.sleep(0.2)
        result = run_user(['./tunnel.sh'])
        assert result.returncode == 0, result.stderr
        pid_file = HOME / 'tunnel.pid'
        assert pid_file.is_file(), 'tunnel.sh did not create tunnel.pid'
        pid_text = pid_file.read_text().strip()
        assert pid_text.isdigit(), f'Invalid tunnel PID: {pid_text!r}'
        pid = int(pid_text)
        assert process_comm(pid) == 'socat', 'Recorded PID is not a running socat process'

        response = None
        last_error = None
        for _ in range(30):
            try:
                with socket.create_connection(('127.0.0.1', 8080), timeout=0.5) as client:
                    client.sendall(token)
                    response = client.recv(4096)
                break
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)
        assert response == token, f'Tunnel did not forward traffic: {last_error}'
    finally:
        if pid is not None and process_comm(pid) == 'socat':
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        backend.terminate()
        try:
            backend.wait(timeout=2)
        except subprocess.TimeoutExpired:
            backend.kill()


def test_pipeline_executes_all_steps_and_handles_third_failure():
    stop_socat_from_pidfile()
    counter = f'/tmp/pipeline_counter_{uuid.uuid4().hex}'
    body = (
        f'counter={shlex.quote(counter)}\n'
        'n=0\n'
        '[ -f "$counter" ] && n=$(cat "$counter")\n'
        'n=$((n + 1))\n'
        'echo "$n" > "$counter"\n'
        '# This fixture would succeed on execution four; a compliant supervisor never reaches it.\n'
        '[ "$n" -ge 4 ] && exit 0\n'
        'exit 1\n'
    )
    (HOME / 'supervisor.log').write_text('STALE CONTENT\n')
    (HOME / 'pipeline_result.txt').write_text('STALE RESULT\n')
    try:
        with mocked_agent(body):
            result = run_user(['./pipeline.sh'], timeout=20)
        assert pathlib.Path(counter).read_text().strip() == '3', (
            f'pipeline/supervisor ran the crashing agent an incorrect number of times; '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )

        failed_path = HOME / 'failed_servers.txt'
        assert failed_path.is_file(), f'File {failed_path} is missing.'
        assert read_nonempty_lines(failed_path) == [
            'server-cache-01,10.0.0.8',
            'server-db-02,10.0.0.12',
        ]

        supervisor_path = HOME / 'supervisor.log'
        assert supervisor_path.is_file(), f'File {supervisor_path} is missing.'
        assert read_nonempty_lines(supervisor_path) == [
            '[WARN] Agent crashed, restarting',
            '[WARN] Agent crashed, restarting',
            '[WARN] Agent crashed, restarting',
            '[ERROR] Max retries reached',
        ]

        result_path = HOME / 'pipeline_result.txt'
        assert result_path.is_file(), f'File {result_path} is missing.'
        assert result_path.read_text().strip() == 'PIPELINE FAILURE'

        pid_file = HOME / 'tunnel.pid'
        assert pid_file.is_file(), f'File {pid_file} is missing.'
        pid_text = pid_file.read_text().strip()
        assert pid_text.isdigit(), f'Contents of {pid_file} must be a valid PID. Got: {pid_text!r}'
        pid = int(pid_text)
        for _ in range(30):
            if process_comm(pid) != 'socat':
                break
            time.sleep(0.1)
        assert process_comm(pid) != 'socat', (
            f'The socat process (PID {pid}) is still running. The pipeline should have terminated it.'
        )
    finally:
        stop_socat_from_pidfile()
        pathlib.Path(counter).unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
