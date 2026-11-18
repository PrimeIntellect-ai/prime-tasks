#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'PY_EOF' > /tmp/behavioral_verify.py
import asyncio
import csv
import json
import os
import random
import shutil
import subprocess
from pathlib import Path

import websockets

HOME = Path('/home/user')
CSV_PATH = HOME / 'endpoints.csv'
REPORT_PATH = HOME / 'security_report.json'
EXCLUDED_DIRS = {'.local', '.cache', '.npm', 'node_modules', '.venv', 'venv', '__pycache__', '.git'}


def candidates():
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        if len(Path(root).relative_to(HOME).parts) > 3:
            dirs[:] = []
        for name in files:
            path = Path(root) / name
            if path == HOME / 'server.py' or path in {CSV_PATH, REPORT_PATH}:
                continue
            try:
                if not path.is_file() or path.stat().st_size > 1024 * 1024:
                    continue
                first = path.open('rb').readline(256).decode('utf-8', 'ignore')
            except OSError:
                continue
            suffix = path.suffix.lower()
            if suffix == '.py':
                cmd = ['python3', str(path)]
            elif suffix == '.js':
                if not shutil.which('node'):
                    continue
                cmd = ['node', str(path)]
            elif suffix in {'.sh', '.bash'}:
                cmd = ['bash', str(path)]
            elif first.startswith('#!') and 'python' in first:
                cmd = ['python3', str(path)]
            elif first.startswith('#!') and ('bash' in first or '/sh' in first):
                cmd = ['bash', str(path)]
            elif first.startswith('#!') and 'node' in first and shutil.which('node'):
                cmd = ['node', str(path)]
            else:
                continue
            found.append((str(path), cmd))
    return sorted(found)


async def exercise(path, cmd):
    nonce = random.SystemRandom().randint(20, 200)
    cases = [
        {'version': f'1.{nonce}.3', 'min': f'1.{nonce}.4', 'reply': 'ok', 'expected': 'INSECURE'},
        {'version': f'2.{nonce}.0', 'min': f'2.{nonce-1}.9', 'reply': 'ok', 'expected': 'SECURE_PASS'},
        {'version': f'3.{nonce}.1', 'min': f'3.{nonce}.1', 'reply': 'error', 'expected': 'SECURE_FAIL'},
    ]
    random.SystemRandom().shuffle(cases)
    events = [[] for _ in cases]
    servers = []

    def make_handler(index):
        async def handler(ws, *args):
            sequence = []
            events[index].append(sequence)
            try:
                async for message in ws:
                    try:
                        data = json.loads(message)
                    except Exception:
                        sequence.append({'__invalid_json__': message})
                        continue
                    sequence.append(data)
                    if data.get('cmd') == 'version':
                        await ws.send(json.dumps({'version': cases[index]['version']}))
                    elif data.get('cmd') == 'test':
                        status = cases[index]['reply'] if data.get('auth') == 'e2e-token' else 'error'
                        await ws.send(json.dumps({'status': status}))
            except Exception:
                pass
        return handler

    try:
        for i in range(len(cases)):
            server = await websockets.serve(make_handler(i), '127.0.0.1', 0)
            servers.append(server)
            port = server.sockets[0].getsockname()[1]
            cases[i]['endpoint'] = f'ws://127.0.0.1:{port}'

        with CSV_PATH.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['endpoint', 'min_version'])
            for case in cases:
                writer.writerow([case['endpoint'], case['min']])
        os.chmod(CSV_PATH, 0o666)

        try:
            REPORT_PATH.unlink()
        except FileNotFoundError:
            pass

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=str(HOME),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            return False
        if proc.returncode != 0 or not REPORT_PATH.is_file():
            return False

        try:
            with REPORT_PATH.open() as f:
                report = json.load(f)
        except Exception:
            return False
        expected = {case['endpoint']: case['expected'] for case in cases}
        if not isinstance(report, dict) or report != expected:
            return False

        for i, case in enumerate(cases):
            sequences = events[i]
            if case['expected'] == 'INSECURE':
                if not any(seq and seq[0] == {'cmd': 'version'} for seq in sequences):
                    return False
                if any(any(isinstance(msg, dict) and msg.get('cmd') == 'test' for msg in seq) for seq in sequences):
                    return False
            else:
                valid = False
                for seq in sequences:
                    if len(seq) >= 2 and seq[0] == {'cmd': 'version'} and seq[1] == {'cmd': 'test', 'auth': 'e2e-token'}:
                        valid = True
                        break
                if not valid:
                    return False
        return True
    finally:
        for server in servers:
            server.close()
        for server in servers:
            await server.wait_closed()


async def main():
    found = candidates()
    if not found:
        raise SystemExit('No Python, Node.js, or Bash orchestrator script was found.')
    for path, cmd in found:
        if await exercise(path, cmd):
            with open('/tmp/winner.json', 'w') as f:
                json.dump({'path': path, 'cmd': cmd}, f)
            return
    raise SystemExit('No submitted script passed the live WebSocket behavioral test.')


asyncio.run(main())
PY_EOF

python3 /tmp/behavioral_verify.py
behavior_rc=$?

# Restore the original task input regardless of the behavioral result.
cat << 'CSV_EOF' > /home/user/endpoints.csv
endpoint,min_version
ws://localhost:9001,1.2.0
ws://localhost:9002,2.0.0
ws://localhost:9003,1.5.5
CSV_EOF
chmod 666 /home/user/endpoints.csv

if [ "$behavior_rc" -ne 0 ]; then
    exit 0
fi

rm -f /home/user/security_report.json
python3 /home/user/server.py >/tmp/original_ws_server.log 2>&1 &
server_pid=$!
sleep 1
if ! kill -0 "$server_pid" 2>/dev/null; then
    exit 0
fi

cat << 'PY_EOF' > /tmp/run_winner.py
import json
import subprocess
with open('/tmp/winner.json') as f:
    command = json.load(f)['cmd']
result = subprocess.run(command, cwd='/home/user', timeout=20)
raise SystemExit(result.returncode)
PY_EOF
python3 /tmp/run_winner.py
run_rc=$?
kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
if [ "$run_rc" -ne 0 ]; then
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_security_report_exists():
    path = "/home/user/security_report.json"
    assert os.path.exists(path), f"File {path} is missing. The security report must be generated by your script."
    assert os.path.isfile(path), f"Path {path} is not a file."

def test_security_report_content():
    path = "/home/user/security_report.json"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {path} does not contain valid JSON. Error: {e}")

    expected = {
        "ws://localhost:9001": "INSECURE",
        "ws://localhost:9002": "SECURE_PASS",
        "ws://localhost:9003": "SECURE_FAIL"
    }

    assert isinstance(data, dict), f"The parsed JSON should be an object (dict), but got {type(data).__name__}."

    for endpoint, expected_status in expected.items():
        assert endpoint in data, f"Endpoint {endpoint} is missing from the report."
        assert data[endpoint] == expected_status, f"Expected status for {endpoint} to be '{expected_status}', but got '{data[endpoint]}'."

    assert len(data) == len(expected), f"The report contains unexpected extra endpoints. Expected {len(expected)} entries, got {len(data)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
