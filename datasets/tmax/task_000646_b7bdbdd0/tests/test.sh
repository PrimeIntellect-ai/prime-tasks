#!/bin/bash
mkdir -p /logs/verifier
reward=0
server_pid=""
backup="/tmp/legacy_analyzer.verifier.$$"
logfile="/tmp/legacy_analyzer_inputs.$$"
compiled="/tmp/stream_processor.verifier.$$"

cleanup() {
    if [ -e "$backup" ]; then
        rm -f /app/legacy_analyzer
        mv "$backup" /app/legacy_analyzer
        chmod 755 /app/legacy_analyzer
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

# The requested artifact must exist and compile as a C program.
if [ ! -f /home/user/stream_processor.c ] || [ ! -s /home/user/stream_processor.c ]; then
    exit 0
fi
if ! gcc /home/user/stream_processor.c -o "$compiled"; then
    exit 0
fi

# Stop any pre-existing listener so the verifier exercises the submitted C source,
# rather than an unrelated process that happened to claim the required port.
python3 - <<'PY'
import os, signal, time

def listeners():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(':', 1)[-1].upper() == '22B8' and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass
    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            pass
    return pids

for pid in listeners():
    try: os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError): pass
time.sleep(0.3)
for pid in listeners():
    try: os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError): pass
time.sleep(0.2)
PY

# Interpose a recorder at the required analyzer path. It forwards each decoded
# message to the real analyzer, while allowing the tests to verify invocation.
mv /app/legacy_analyzer "$backup" || exit 0
: > "$logfile"
cat > /app/legacy_analyzer <<EOF
#!/bin/sh
IFS= read -r line || exit 1
printf '%s\n' "\$line" >> '$logfile'
printf '%s\n' "\$line" | '$backup'
EOF
chmod 755 /app/legacy_analyzer

"$compiled" >/tmp/stream_processor.verifier.log 2>&1 &
server_pid=$!
export VERIFIER_ANALYZER="$backup"
export VERIFIER_ANALYZER_LOG="$logfile"
export VERIFIER_COMPILED="$compiled"
export VERIFIER_SERVER_PID="$server_pid"

# Confirm that the listener belongs to the freshly compiled submitted program.
if ! python3 - <<'PY'
import os, time, sys
compiled = os.environ['VERIFIER_COMPILED']
expected = os.path.realpath(compiled)
deadline = time.time() + 5
while time.time() < deadline:
    inodes = set()
    try:
        with open('/proc/net/tcp') as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1] == '0100007F:22B8' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f'/proc/{name}/exe')
            if exe != expected:
                continue
            for fd in os.listdir(f'/proc/{name}/fd'):
                try:
                    target = os.readlink(f'/proc/{name}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    sys.exit(0)
        except OSError:
            pass
    time.sleep(0.05)
sys.exit(1)
PY
then
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import os
import secrets
import socket
import string
import subprocess
import pytest

HOST = '127.0.0.1'
PORT = 8888
ANALYZER = os.environ['VERIFIER_ANALYZER']
ANALYZER_LOG = os.environ['VERIFIER_ANALYZER_LOG']
expected_analyzer_inputs = []

def send_and_receive(payload: str, expected_lines=1, timeout=5.0) -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((HOST, PORT))
            s.sendall(payload.encode('utf-8'))
            data = b''
            while data.count(b'\n') < expected_lines:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            return data.decode('utf-8')
    except ConnectionRefusedError:
        pytest.fail('Connection refused. Make sure the C server is running and listening on 127.0.0.1:8888.')
    except socket.timeout:
        pytest.fail("Socket timed out. The server accepted the connection but didn't respond in time.")
    except Exception as e:
        pytest.fail(f'Unexpected socket error: {e}')

def oracle_score(message: str) -> int:
    result = subprocess.run(
        [ANALYZER], input=(message + '\n').encode(), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=3, check=True
    )
    return int(result.stdout.decode().strip())

def test_server_response_basic():
    payload = '{"ts": "2023-01-01T00:00:00Z", "msg": "Test\\u0021"}\n'
    response = send_and_receive(payload).strip()
    if '999' in response:
        pytest.fail(f"Server returned anomaly score 999 indicating unescaped unicode '\\' was sent to the analyzer. Response: {response}")
    expected_analyzer_inputs.append('Test!')
    expected = '1672531200,49'
    assert response == expected, f"Expected '{expected}', got '{response}'"

def test_server_response_complex():
    payload = '{"ts": "2023-11-15T08:30:00Z", "msg": "High CPU load on db-node-01\\u002e"}\n'
    response = send_and_receive(payload).strip()
    if '999' in response:
        pytest.fail(f"Server returned anomaly score 999 indicating unescaped unicode '\\' was sent to the analyzer. Response: {response}")
    expected_analyzer_inputs.append('High CPU load on db-node-01.')
    expected = '1700037000,85'
    assert response == expected, f"Expected '{expected}', got '{response}'"

def test_randomized_json_lines_and_analyzer_invocation():
    cases = []
    escaped_chars = ['!', '.', '?', '#', '@', ':', ';', '+', '-', '_', '=']
    base_epoch = calendar.timegm((2010, 1, 1, 0, 0, 0))
    span = calendar.timegm((2035, 1, 1, 0, 0, 0)) - base_epoch

    for _ in range(8):
        epoch = base_epoch + secrets.randbelow(span)
        ts = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(18))
        chosen = [secrets.choice(escaped_chars) for _ in range(3)]
        message = token + ' live event ' + ''.join(chosen)
        encoded_tail = ''.join('\\u%04x' % ord(ch) for ch in chosen)
        payload = '{"msg":"' + token + ' live event ' + encoded_tail + '","ts":"' + ts + '"}\n'
        expected = f'{epoch},{oracle_score(message)}'
        cases.append((payload, expected, message))

    # Exercise multiple JSON lines over one TCP stream, not merely connection order.
    response = send_and_receive(''.join(c[0] for c in cases), expected_lines=len(cases))
    lines = response.splitlines()
    assert lines == [c[1] for c in cases]
    expected_analyzer_inputs.extend(c[2] for c in cases)

    with open(ANALYZER_LOG, encoding='utf-8') as f:
        observed = [line.rstrip('\n') for line in f]
    for message in expected_analyzer_inputs:
        assert message in observed, f'Decoded message was not fed to /app/legacy_analyzer: {message!r}'
    assert all('\\u' not in message for message in observed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
