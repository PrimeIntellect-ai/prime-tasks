#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

# Preserve the original end-to-end assertions against the service left running by the agent.
cat << 'PY' > /tmp/test_original_state.py
import socket
import pytest

HOST = "127.0.0.1"
PORT = 8888
PASSCODE = "849302"
EXPECTED_CSV = """ServerName,ConfigKey,ConfigValue
prod-srv-01,CACHE_SIZE,1024
prod-srv-01,DB_PASSWORD,***
prod-srv-01,OS_VERSION,Ubuntu 22.04
win-srv-02,ADMIN_USER,sysadmin
win-srv-02,API_TOKEN,***
win-srv-02,MAX_WORKERS,64
"""

def test_tcp_server_incorrect_passcode():
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.sendall(b"000000\n")
            response = s.recv(4096)
            assert response == b"", f"Expected connection to be dropped, but got: {response}"
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to TCP server at {HOST}:{PORT}")
    except socket.timeout:
        pytest.fail("Server timed out without dropping the connection for an invalid passcode.")

def test_tcp_server_correct_passcode():
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.sendall(f"{PASSCODE}\n".encode())
            response_data = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response_data += chunk
        response_str = response_data.decode("utf-8").replace("\r\n", "\n")
        assert response_str.strip() == EXPECTED_CSV.strip(), (
            f"Expected CSV response:\n{EXPECTED_CSV}\n\nActual CSV response:\n{response_str}"
        )
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to TCP server at {HOST}:{PORT}")
    except socket.timeout:
        pytest.fail("Server timed out while sending data.")
    except UnicodeDecodeError:
        pytest.fail("Server response was not valid UTF-8.")
PY
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short

# The requested artifact must exist and independently compile as C++.
test -f /home/user/config_svc.cpp
test -s /home/user/config_svc.cpp
test ! -L /home/user/config_svc.cpp
timeout 30 g++ -std=c++17 -O2 -pthread /home/user/config_svc.cpp -o /tmp/config_svc_verified

# Stop whichever process currently owns the required listening port.
cat << 'PY' > /tmp/kill_port.py
import os, signal, time

def listener_inodes():
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(':', 1)[1], 16) == 8888 and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found

def owners(inodes):
    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{name}/fd'):
                try:
                    target = os.readlink(f'/proc/{name}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result

pids = owners(listener_inodes())
for pid in pids:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
time.sleep(0.5)
for pid in pids:
    try: os.kill(pid, signal.SIGKILL)
    except ProcessLookupError: pass
PY
python3 /tmp/kill_port.py

# Replace both the authentication image and configuration corpus with unpredictable
# fixtures, including UTF-8, UTF-16LE, mixed-case secret keys, and non-ASCII values.
rm -f /app/configs/*
python3 << 'PY'
from PIL import Image, ImageDraw, ImageFont
import csv, glob, io, os, secrets, subprocess

while True:
    passcode = ''.join(str(secrets.randbelow(10)) for _ in range(6))
    if passcode != '849302':
        break

font_paths = glob.glob('/usr/share/fonts/**/*DejaVuSans-Bold.ttf', recursive=True)
font = ImageFont.truetype(font_paths[0], 64) if font_paths else ImageFont.load_default(size=64)
image = Image.new('RGB', (360, 110), 'white')
draw = ImageDraw.Draw(image)
draw.text((35, 12), passcode, font=font, fill='black')
image.save('/app/auth_code.png')

ocr = subprocess.check_output(
    ['tesseract', '/app/auth_code.png', 'stdout'], stderr=subprocess.DEVNULL, text=True
)
recognized = ''.join(c for c in ocr if c.isdigit())
assert recognized == passcode, (passcode, ocr)
with open('/tmp/dynamic_passcode', 'w') as f:
    f.write(passcode)

suffix = secrets.token_hex(5)
fixtures = [
    ('utf8_a.csv', 'utf-8',
     ['ServerName', 'plain_key', 'Db_PaSsWoRd_backup', 'ZETA'],
     ['zeta-' + suffix, 'München-' + suffix, 'must-not-leak-' + suffix, '9']),
    ('legacy.csv', 'utf-16le',
     ['ServerName', 'MAX_WORKERS', 'Api_ToKeN_v2', 'ADMIN_USER'],
     ['alpha-' + suffix, '73', 'token-' + suffix, 'ops-' + suffix]),
    ('utf8_b.csv', 'utf-8',
     ['ServerName', 'x_secret_setting', 'CACHE_SIZE', 'REGION'],
     ['middle-' + suffix, 'secret-' + suffix, '2049', '東京-' + suffix]),
    ('legacy2.csv', 'utf-16le',
     ['ServerName', 'PORT', 'PUBLIC_VALUE'],
     ['beta-' + suffix, '8123', 'value-' + secrets.token_hex(4)]),
]
for filename, encoding, header, values in fixtures:
    buf = io.StringIO(newline='')
    writer = csv.writer(buf, lineterminator='\n')
    writer.writerow(header)
    writer.writerow(values)
    with open('/app/configs/' + filename, 'wb') as f:
        f.write(buf.getvalue().encode(encoding))
PY

/tmp/config_svc_verified >/tmp/config_svc_verified.log 2>&1 &
SVC_PID=$!
cleanup() {
    kill "$SVC_PID" 2>/dev/null || true
    python3 /tmp/kill_port.py >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Derive expected output from the newly generated files rather than trusting a
# fixed answer, then exercise authentication and the rebuilt service.
cat << 'PY' > /tmp/test_dynamic_state.py
import csv
import io
import os
import socket
import subprocess
import time

HOST, PORT = '127.0.0.1', 8888

ocr = subprocess.check_output(
    ['tesseract', '/app/auth_code.png', 'stdout'], stderr=subprocess.DEVNULL, text=True
)
passcode = ''.join(c for c in ocr if c.isdigit())
assert len(passcode) == 6
assert passcode == open('/tmp/dynamic_passcode').read()

expected = []
for name in os.listdir('/app/configs'):
    path = os.path.join('/app/configs', name)
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16le') if b'\x00' in raw[:100] else raw.decode('utf-8')
    rows = list(csv.reader(io.StringIO(text)))
    assert len(rows) == 2 and len(rows[0]) == len(rows[1])
    server = rows[1][0]
    for key, value in zip(rows[0][1:], rows[1][1:]):
        if any(marker in key.upper() for marker in ('PASSWORD', 'TOKEN', 'SECRET')):
            value = '***'
        expected.append([server, key, value])
expected.sort(key=lambda row: (row[0], row[1]))

# Retry only connection establishment while the freshly launched binary starts.
deadline = time.time() + 8
while True:
    try:
        probe = socket.create_connection((HOST, PORT), timeout=1)
        break
    except OSError:
        if time.time() >= deadline:
            raise AssertionError('Recompiled service did not listen on 127.0.0.1:8888')
        time.sleep(0.1)

wrong = ''.join('1' if c == '0' else '0' for c in passcode)
with probe:
    probe.settimeout(5)
    probe.sendall((wrong + '\n').encode())
    try:
        rejected = probe.recv(4096)
    except ConnectionResetError:
        rejected = b''
    assert rejected == b'', f'invalid passcode produced data: {rejected!r}'

with socket.create_connection((HOST, PORT), timeout=5) as s:
    s.settimeout(5)
    s.sendall((passcode + '\n').encode())
    chunks = []
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        chunks.append(chunk)
raw_response = b''.join(chunks)
text = raw_response.decode('utf-8').replace('\r\n', '\n')
rows = list(csv.reader(io.StringIO(text)))
assert rows, 'service returned no CSV data'
assert rows[0] == ['ServerName', 'ConfigKey', 'ConfigValue'], rows[0]
assert rows[1:] == expected, f'expected {expected!r}, got {rows[1:]!r}'
PY
python3 /tmp/test_dynamic_state.py

); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
