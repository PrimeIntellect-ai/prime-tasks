#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import stat
import subprocess
import time
import uuid
import shlex
import pytest

HOST = '127.0.0.1'
PORT = 7777
SOURCE = '/home/user/sensor_server.cpp'
EXECUTABLE = '/home/user/sensor_server'
CALC = '/app/dist_calc'


def send_tcp_request(host, port, message):
    """Preserve the original request behavior: read through the first newline."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect((host, port))
            s.sendall(message.encode('utf-8'))
            response = b''
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                response += chunk
                if b'\n' in response:
                    break
            return response.decode('utf-8')
    except Exception as e:
        pytest.fail(f'Failed to communicate with TCP server at {host}:{port}: {e}')


def send_request_require_close(message):
    """Read until EOF, requiring the server to close the connection."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect((HOST, PORT))
            s.sendall(message.encode('utf-8'))
            response = b''
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    return response.decode('utf-8')
                response += chunk
                assert len(response) < 65536, 'Server returned an unreasonably large response'
    except socket.timeout:
        pytest.fail('Server did not close the client connection after responding')
    except Exception as e:
        pytest.fail(f'Failed to communicate with TCP server at {HOST}:{PORT}: {e}')


def oracle_score(record_id, values):
    payload = ''.join(
        f'{record_id} {axis} {text}\n'
        for axis, text in zip(('X', 'Y', 'Z'), values)
    )
    result = subprocess.run(
        [CALC], input=payload, text=True, capture_output=True, timeout=5, check=True
    )
    assert re.fullmatch(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)\n', result.stdout)
    return result.stdout


def running_server_pids():
    wanted = os.path.realpath(EXECUTABLE)
    found = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            target = os.readlink(f'/proc/{name}/exe')
            if target.endswith(' (deleted)'):
                target = target[:-10]
            if os.path.realpath(target) == wanted:
                found.append(int(name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return found


def zombie_descendants(roots):
    processes = {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            fields = open(f'/proc/{name}/stat').read().split()
            processes[int(name)] = (fields[2], int(fields[3]))
        except (FileNotFoundError, PermissionError, OSError, ValueError, IndexError):
            pass
    descendants = set(roots)
    changed = True
    while changed:
        changed = False
        for pid, (_, ppid) in processes.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return [pid for pid in descendants if pid not in roots and processes.get(pid, ('', 0))[0] == 'Z']


def test_artifacts_exist_and_server_is_running():
    source_stat = os.stat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f'{SOURCE} is not a regular file'
    assert source_stat.st_size > 0, f'{SOURCE} is empty'

    executable_stat = os.stat(EXECUTABLE)
    assert stat.S_ISREG(executable_stat.st_mode), f'{EXECUTABLE} is not a regular file'
    assert os.access(EXECUTABLE, os.X_OK), f'{EXECUTABLE} is not executable'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXECUTABLE} is not a compiled ELF executable'

    assert running_server_pids(), f'{EXECUTABLE} is not running'


def test_tcp_server_valid_data_1():
    response = send_tcp_request(HOST, PORT, 'TEST1,2.0,3.0,4.0\n')
    assert response == 'SCORE: 29.00\n', f"Expected 'SCORE: 29.00\\n', got {response!r}"


def test_tcp_server_valid_data_2():
    response = send_tcp_request(HOST, PORT, 'B99,-10.0,0.0,5.0\n')
    assert response == 'SCORE: 125.00\n', f"Expected 'SCORE: 125.00\\n', got {response!r}"


def test_tcp_server_invalid_data_out_of_bounds():
    response = send_tcp_request(HOST, PORT, 'ERR1,150.0,10.0,10.0\n')
    assert response == 'ERR: INVALID_DATA\n', f"Expected 'ERR: INVALID_DATA\\n', got {response!r}"


def test_tcp_server_invalid_data_format():
    response = send_tcp_request(HOST, PORT, 'BAD,1.0\n')
    assert response == 'ERR: INVALID_DATA\n', f"Expected 'ERR: INVALID_DATA\\n', got {response!r}"


def test_dynamic_valid_requests_and_connection_close():
    cases = [
        ('-100.0', '100.0', '0'),
        ('99.5', '-88.25', '17.75'),
        ('0.125', '-0.5', '73.0'),
        ('-42', '31.25', '-19.5'),
    ]
    for values in cases:
        record_id = 'R' + uuid.uuid4().hex
        expected = oracle_score(record_id, values)
        response = send_request_require_close(f'{record_id},{values[0]},{values[1]},{values[2]}\n')
        assert response == f'SCORE: {expected}', (
            f'Wrong response for dynamically generated request {record_id}: {response!r}'
        )


def test_comprehensive_invalid_input_validation():
    bad_messages = [
        'R,100.001,0,0\n',
        'R,-100.001,0,0\n',
        'R,0,100.001,0\n',
        'R,0,0,-100.001\n',
        'R,nan,0,0\n',
        'R,inf,0,0\n',
        'R,-inf,0,0\n',
        'R,1x,2,3\n',
        'R,1,2,3,4\n',
        'R,1,2,\n',
        ',1,2,3\n',
        'R;1;2;3\n',
    ]
    for message in bad_messages:
        assert send_request_require_close(message) == 'ERR: INVALID_DATA\n', message


def test_server_invokes_dist_calc_with_long_format_and_uses_stdout():
    token = uuid.uuid4().hex
    capture = f'/tmp/dist_calc_input_{token}'
    backup = f'/app/.dist_calc_backup_{token}'
    sentinel = f'{7000 + (int(token[:6], 16) % 2000)}.{int(token[6:8], 16) % 100:02d}'
    original_mode = os.stat(CALC).st_mode

    os.rename(CALC, backup)
    try:
        with open(CALC, 'w') as f:
            f.write('#!/bin/sh\n')
            f.write(f'cat > {shlex.quote(capture)}\n')
            f.write(f"printf '%s\\n' {shlex.quote(sentinel)}\n")
        os.chmod(CALC, 0o755)

        record_id = 'HOOK' + token
        values = ('12.375', '-7.25', '0.5')
        response = send_request_require_close(
            f'{record_id},{values[0]},{values[1]},{values[2]}\n'
        )
        assert response == f'SCORE: {sentinel}\n', (
            'Server did not return the stdout produced by /app/dist_calc'
        )
        assert os.path.isfile(capture), 'Server did not invoke /app/dist_calc'

        lines = open(capture).read().splitlines()
        assert len(lines) == 3, f'Legacy input must contain exactly three lines: {lines!r}'
        for line, axis, expected in zip(lines, ('X', 'Y', 'Z'), values):
            fields = line.split()
            assert len(fields) == 3, f'Malformed long-format line: {line!r}'
            assert fields[0] == record_id and fields[1] == axis
            assert float(fields[2]) == float(expected)
    finally:
        try:
            os.unlink(CALC)
        except FileNotFoundError:
            pass
        os.rename(backup, CALC)
        os.chmod(CALC, stat.S_IMODE(original_mode))
        try:
            os.unlink(capture)
        except FileNotFoundError:
            pass


def test_no_zombie_children_after_requests():
    time.sleep(0.5)
    pids = running_server_pids()
    assert pids, 'Compiled server stopped running during verification'
    zombies = zombie_descendants(pids)
    assert not zombies, f'Server left zombie child processes: {zombies}'


def test_cron_file_exists_and_content():
    cron_path = '/home/user/pipeline_cron'
    assert os.path.isfile(cron_path), f'Cron file {cron_path} does not exist.'
    with open(cron_path, 'r') as f:
        content = f.read()

    pattern = re.compile(r'^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/batch_poll\.sh\s*$')
    assert pattern.fullmatch(content), (
        f'{cron_path} must contain exactly the required cron expression. Content:\n{content}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
