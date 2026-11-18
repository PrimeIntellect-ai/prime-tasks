#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import uuid

PAYLOAD_C = pathlib.Path('/home/user/payload.c')
PAYLOAD_BIN = pathlib.Path('/home/user/payload.bin')
HARNESS = pathlib.Path('/home/user/test_harness.py')
WAF_LOGS = pathlib.Path('/home/user/waf_logs.json')
REPORT = pathlib.Path('/home/user/final_report.json')


def run_json(path, timeout=5):
    result = subprocess.run([str(path)], capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, f'{path} exited with {result.returncode}: {result.stderr}'
    try:
        return result.stdout.strip(), json.loads(result.stdout)
    except Exception as exc:
        assert False, f'Failed to parse output from {path} as JSON: {exc}'


def test_payload_bin_exists_and_executable():
    path = '/home/user/payload.bin'
    assert os.path.isfile(path), f'File {path} is missing.'
    assert os.access(path, os.X_OK), f'File {path} is not executable.'


def test_payload_bin_output():
    path = '/home/user/payload.bin'
    assert os.path.isfile(path), f'File {path} is missing.'

    try:
        result = subprocess.run([path], capture_output=True, text=True, timeout=2)
        output = result.stdout.strip()
        data = json.loads(output)
    except Exception as e:
        assert False, f'Failed to execute {path} or parse its output as JSON: {e}'

    assert data.get('status') == 'exploited', "Payload output missing or incorrect 'status' field."
    assert data.get('env') == 'staging', "Payload output 'env' should be 'staging' (compiled with MOCK_MODE)."


def test_payload_is_static_elf():
    assert PAYLOAD_BIN.read_bytes()[:4] == b'\x7fELF', 'payload.bin must be an ELF executable, not a script.'
    result = subprocess.run(['readelf', '-lW', str(PAYLOAD_BIN)], capture_output=True, text=True)
    assert result.returncode == 0, f'Could not inspect payload.bin: {result.stderr}'
    assert 'INTERP' not in result.stdout, 'payload.bin has a program interpreter and is dynamically linked.'


def test_payload_source_has_required_conditional_behavior():
    assert PAYLOAD_C.is_file(), 'File /home/user/payload.c is missing.'
    with tempfile.TemporaryDirectory() as td:
        normal = pathlib.Path(td) / 'normal'
        mock = pathlib.Path(td) / 'mock'
        for output, flags in ((normal, []), (mock, ['-DMOCK_MODE'])):
            result = subprocess.run(
                ['gcc', str(PAYLOAD_C), '-o', str(output), *flags],
                capture_output=True, text=True, timeout=20
            )
            assert result.returncode == 0, f'payload.c failed to compile with {flags}: {result.stderr}'

        normal_text, normal_data = run_json(normal)
        mock_text, mock_data = run_json(mock)
        assert normal_text == '{"status": "exploited", "env": "production"}'
        assert mock_text == '{"status": "exploited", "env": "staging"}'
        assert normal_data == {'status': 'exploited', 'env': 'production'}
        assert mock_data == {'status': 'exploited', 'env': 'staging'}


def test_final_report_json():
    path = '/home/user/final_report.json'
    assert os.path.isfile(path), f'File {path} is missing. The test harness did not generate it.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {path} is not valid JSON.'

    assert 'payload_result' in data, "final_report.json is missing 'payload_result' key."
    assert 'blocked_agents' in data, "final_report.json is missing 'blocked_agents' key."

    assert data['payload_result'].get('env') == 'staging', "final_report.json payload_result.env is not 'staging'."
    assert data['payload_result'].get('status') == 'exploited', "final_report.json payload_result.status is not 'exploited'."

    expected_agents = ['Nmap Scripting Engine', 'curl/7.68.0', 'sqlmap/1.5.8.2#dev']
    assert data['blocked_agents'] == expected_agents, f"final_report.json blocked_agents does not match expected list. Got {data['blocked_agents']}"


def test_harness_uses_dynamic_inputs_and_http_post():
    assert HARNESS.is_file(), 'File /home/user/test_harness.py is missing.'

    token = uuid.uuid4().hex
    payload_result = {
        'status': 'probe_' + token,
        'env': 'dynamic_' + token,
        'nonce': token,
    }
    blocked = ['Alpha-' + token, 'Zulu-' + token, 'Alpha-' + token]
    expected_agents = sorted(set(blocked))
    logs = [
        {'action': 'blocked', 'user_agent': blocked[1]},
        {'action': 'allowed', 'user_agent': 'Ignore-' + token},
        {'action': 'blocked', 'user_agent': blocked[0]},
        {'action': 'blocked', 'user_agent': blocked[2]},
        {'action': 'BLOCKED', 'user_agent': 'WrongCase-' + token},
    ]
    expected = {'payload_result': payload_result, 'blocked_agents': expected_agents}

    old_waf = WAF_LOGS.read_bytes()
    old_payload = PAYLOAD_BIN.read_bytes()
    old_payload_mode = stat.S_IMODE(PAYLOAD_BIN.stat().st_mode)
    old_report = REPORT.read_bytes() if REPORT.exists() else None

    with tempfile.TemporaryDirectory() as td:
        td_path = pathlib.Path(td)
        event_log = td_path / 'socket-events.jsonl'
        sitecustomize = td_path / 'sitecustomize.py'
        sitecustomize.write_text(r'''import json
import os
import socket

_log_path = os.environ.get('SOCKET_EVENT_LOG')

def _log(kind, value):
    if not _log_path:
        return
    fd = os.open(_log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, (json.dumps({'kind': kind, 'value': value}) + '\n').encode())
    finally:
        os.close(fd)

_old_bind = socket.socket.bind
_old_listen = socket.socket.listen
_old_connect = socket.socket.connect
_old_connect_ex = socket.socket.connect_ex
_old_accept = socket.socket.accept
_old_sendall = socket.socket.sendall

def bind(self, address):
    _log('bind', address)
    return _old_bind(self, address)

def listen(self, backlog=0):
    _log('listen', backlog)
    return _old_listen(self, backlog)

def connect(self, address):
    _log('connect', address)
    return _old_connect(self, address)

def connect_ex(self, address):
    _log('connect_ex', address)
    return _old_connect_ex(self, address)

def accept(self):
    result = _old_accept(self)
    _log('accept', result[1])
    return result

def sendall(self, data, *args, **kwargs):
    try:
        shown = bytes(data).decode('latin1')
    except Exception:
        shown = repr(data)
    _log('sendall', shown)
    return _old_sendall(self, data, *args, **kwargs)

socket.socket.bind = bind
socket.socket.listen = listen
socket.socket.connect = connect
socket.socket.connect_ex = connect_ex
socket.socket.accept = accept
socket.socket.sendall = sendall
''')

        try:
            WAF_LOGS.write_text(json.dumps(logs))

            payload_text = json.dumps(payload_result)
            c_literal = json.dumps(payload_text)
            probe_c = td_path / 'probe.c'
            probe_c.write_text('#include <stdio.h>\nint main(void) { puts(' + c_literal + '); return 0; }\n')
            compile_result = subprocess.run(
                ['gcc', '-static', str(probe_c), '-o', str(PAYLOAD_BIN)],
                capture_output=True, text=True, timeout=30
            )
            assert compile_result.returncode == 0, compile_result.stderr
            if REPORT.exists():
                REPORT.unlink()

            env = os.environ.copy()
            env['PYTHONPATH'] = td + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
            env['SOCKET_EVENT_LOG'] = str(event_log)
            result = subprocess.run(
                ['python3', str(HARNESS)], cwd='/home/user', env=env,
                capture_output=True, text=True, timeout=15
            )
            assert result.returncode == 0, f'test_harness.py failed: stdout={result.stdout!r} stderr={result.stderr!r}'
            assert REPORT.is_file(), 'The harness did not generate final_report.json.'

            report_text = REPORT.read_text()
            assert json.loads(report_text) == expected, 'Harness did not derive its report from the runtime payload and WAF log.'
            formatted = json.dumps(expected, indent=4)
            assert report_text in (formatted, formatted + '\n'), 'final_report.json is not formatted with 4-space indentation.'

            assert event_log.exists(), 'No socket activity was observed while running the harness.'
            events = [json.loads(line) for line in event_log.read_text().splitlines() if line.strip()]
            assert any(e['kind'] == 'bind' and e['value'][0] == '127.0.0.1' and e['value'][1] == 8000 for e in events), \
                'Harness did not bind an HTTP server to 127.0.0.1:8000.'
            assert any(e['kind'] == 'listen' for e in events), 'Harness did not listen for HTTP requests.'
            assert any(e['kind'] in ('connect', 'connect_ex') and e['value'][0] == '127.0.0.1' and e['value'][1] == 8000 for e in events), \
                'The main thread did not connect to the local report server.'
            assert any(e['kind'] == 'accept' for e in events), 'The local server did not accept a connection.'
            sent = ''.join(e['value'] for e in events if e['kind'] == 'sendall')
            assert 'POST /report ' in sent, 'No HTTP POST to /report was observed.'
            assert token in sent, 'The POST body did not contain the dynamically generated report data.'
        finally:
            WAF_LOGS.write_bytes(old_waf)
            PAYLOAD_BIN.write_bytes(old_payload)
            PAYLOAD_BIN.chmod(old_payload_mode)
            if old_report is None:
                if REPORT.exists():
                    REPORT.unlink()
            else:
                REPORT.write_bytes(old_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
