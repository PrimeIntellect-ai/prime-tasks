#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

REAL_TOOL="/tmp/arc_tool.real.$$"
CALL_LOG="/tmp/arc_tool.calls.$$"
CONTROL_FILE="/tmp/arc_tool.pause.$$"
ENTERED_FILE="/tmp/arc_tool.entered.$$"
NOVEL_DATE="2077-12-$(printf '%02d' $((($$ % 27) + 1)))"
export REAL_TOOL CALL_LOG CONTROL_FILE ENTERED_FILE NOVEL_DATE

cleanup() {
    rm -f "$CONTROL_FILE" "$ENTERED_FILE" "$CALL_LOG"
    rm -f "/home/user/logs/app_${NOVEL_DATE}.log"
    if [ -e "$REAL_TOOL" ]; then
        rm -f /app/arc_tool
        mv "$REAL_TOOL" /app/arc_tool
        chmod +x /app/arc_tool
    fi
}
trap cleanup EXIT

if [ ! -x /app/arc_tool ]; then
    exit 0
fi
if ! python3 -c 'import sys; sys.exit(0 if open("/app/arc_tool", "rb").read(4) == b"\x7fELF" else 1)'; then
    exit 0
fi

mv /app/arc_tool "$REAL_TOOL" || exit 0
cat > /app/arc_tool <<EOF
#!/bin/bash
printf '%s\t%s\n' "\$1" "\$2" >> "$CALL_LOG"
if [ -e "$CONTROL_FILE" ]; then
    : > "$ENTERED_FILE"
    sleep 2
fi
exec "$REAL_TOOL" "\$@"
EOF
chmod 755 /app/arc_tool
: > "$CALL_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import socket
import os
import glob
import pytest
import threading
import re
import subprocess
import tempfile
import time
import uuid

HOST = '127.0.0.1'
PORT = 9000
REAL_TOOL = os.environ['REAL_TOOL']
CALL_LOG = os.environ['CALL_LOG']
CONTROL_FILE = os.environ['CONTROL_FILE']
ENTERED_FILE = os.environ['ENTERED_FILE']
NOVEL_DATE = os.environ['NOVEL_DATE']
NOVEL_LOG = f'/home/user/logs/app_{NOVEL_DATE}.log'

@pytest.fixture(scope='session', autouse=True)
def dynamic_log_fixture():
    token = uuid.uuid4().hex
    content = (
        '--- RECORD START ---\n'
        f'DATE: {NOVEL_DATE}\n'
        'LEVEL: INFO\n'
        f'MSG: distractor-{token}\n'
        '--- RECORD END ---\n'
        '--- RECORD START ---\n'
        f'DATE: {NOVEL_DATE}\n'
        'LEVEL: CRITICAL\n'
        f'MSG: first-random-{token}\n'
        'DETAIL: dynamically-created multi-line record\n'
        '--- RECORD END ---\n'
        '--- RECORD START ---\n'
        f'DATE: {NOVEL_DATE}\n'
        'LEVEL: WARNING\n'
        'MSG: LEVEL: CRITICAL is not a level field here\n'
        '--- RECORD END ---\n'
        '--- RECORD START ---\n'
        f'DATE: {NOVEL_DATE}\n'
        'LEVEL: CRITICAL\n'
        f'MSG: second-random-{token[::-1]}\n'
        '--- RECORD END ---\n'
    )
    with open(NOVEL_LOG, 'w') as f:
        f.write(content)
    yield
    try:
        os.unlink(NOVEL_LOG)
    except FileNotFoundError:
        pass

def get_log_dates():
    logs_dir = '/home/user/logs'
    log_files = glob.glob(os.path.join(logs_dir, 'app_*.log'))
    dates = []
    for lf in log_files:
        m = re.search(r'app_(\d{4}-\d{2}-\d{2})\.log', lf)
        if m:
            dates.append(m.group(1))
    return sorted(dates)

def get_expected_critical_records(date):
    log_file = f'/home/user/logs/app_{date}.log'
    if not os.path.exists(log_file):
        return ""

    with open(log_file, 'r') as f:
        content = f.read()

    records = []
    current_record = []
    in_record = False
    is_critical = False

    for line in content.splitlines(True):
        if line.strip() == "--- RECORD START ---":
            in_record = True
            current_record = [line]
            is_critical = False
        elif in_record:
            current_record.append(line)
            if line.strip() == "LEVEL: CRITICAL":
                is_critical = True
            elif line.strip() == "--- RECORD END ---":
                in_record = False
                if is_critical:
                    records.append("".join(current_record))

    return "".join(records)

def send_request(date):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(f"ARCHIVE {date}\n".encode())

        header = b""
        while b"\n" not in header:
            chunk = s.recv(1)
            if not chunk:
                break
            header += chunk
            if len(header) > 100:
                break

        if not header.endswith(b"\n"):
            return None, b"Connection closed or no newline in header"

        header_str = header.decode().strip()
        if header_str.startswith("ERROR"):
            return header_str, b""

        if not header_str.startswith("SUCCESS"):
            return header_str, b""

        parts = header_str.split()
        if len(parts) != 2:
            return header_str, b"Invalid SUCCESS format"

        size = int(parts[1])
        payload = b""
        while len(payload) < size:
            chunk = s.recv(size - len(payload))
            if not chunk:
                break
            payload += chunk

        return header_str, payload
    except Exception as e:
        return "EXCEPTION", str(e).encode()
    finally:
        s.close()

def decrypt_payload(payload):
    if len(payload) < 4:
        return False, b"Payload too short"
    if payload[:4] != b"ARC1":
        return False, b"Missing ARC1 header"

    decrypted = bytearray()
    for byte in payload[4:]:
        decrypted.append(byte ^ 0x4B)
    return True, bytes(decrypted)

def oracle_archive(data):
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, 'input.txt')
        out = os.path.join(td, 'output.arc')
        with open(inp, 'wb') as f:
            f.write(data)
        subprocess.run([REAL_TOOL, inp, out], check=True, timeout=5)
        with open(out, 'rb') as f:
            return f.read()

def invocation_count():
    try:
        with open(CALL_LOG, 'r') as f:
            return sum(1 for line in f if line.strip())
    except FileNotFoundError:
        return 0

def test_service_listening():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        result = s.connect_ex((HOST, PORT))
        assert result == 0, f"Service is not listening on {HOST}:{PORT}"
    finally:
        s.close()

def test_not_found():
    header, payload = send_request("2099-01-01")
    assert header == "ERROR NOT_FOUND", f"Expected ERROR NOT_FOUND, got {header}"

def test_valid_archive():
    dates = get_log_dates()
    assert len(dates) > 0, "No log dates found to test"

    date = dates[0]
    expected_records = get_expected_critical_records(date)

    header, payload = send_request(date)
    assert header is not None, "Failed to get response"
    assert header.startswith("SUCCESS"), f"Expected SUCCESS, got {header}"

    parts = header.split()
    assert len(payload) == int(parts[1]), "Payload size does not match header"

    success, decrypted = decrypt_payload(payload)
    assert success, f"Decryption failed: {decrypted.decode(errors='ignore')}"
    assert decrypted.decode() == expected_records, "Decrypted payload does not match expected CRITICAL records"

def test_dynamic_log_and_arc_tool_invocation():
    before = invocation_count()
    expected_records = get_expected_critical_records(NOVEL_DATE).encode()
    expected_payload = oracle_archive(expected_records)

    header, payload = send_request(NOVEL_DATE)
    assert header is not None and header.startswith('SUCCESS'), f"Expected SUCCESS, got {header}"
    assert len(payload) == int(header.split()[1]), "Payload size does not match header"
    assert payload == expected_payload, "Payload differs from output produced by /app/arc_tool"

    success, decrypted = decrypt_payload(payload)
    assert success, "Dynamic payload is not a valid ARC1 archive"
    assert decrypted == expected_records, "Server did not dynamically parse the newly-created log"
    assert invocation_count() >= before + 1, "Server did not invoke /app/arc_tool for the request"

def test_lock_is_held_during_compression():
    for path in (CONTROL_FILE, ENTERED_FILE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    open(CONTROL_FILE, 'w').close()

    result = []
    t = threading.Thread(target=lambda: result.append(send_request(NOVEL_DATE)))
    t.start()

    deadline = time.time() + 4
    while time.time() < deadline and not os.path.exists(ENTERED_FILE):
        time.sleep(0.02)
    assert os.path.exists(ENTERED_FILE), "Timed out waiting for /app/arc_tool invocation"
    assert os.path.exists('/tmp/archive.lock'), "Required lockfile /tmp/archive.lock does not exist"

    probe = subprocess.run(
        ['flock', '-n', '/tmp/archive.lock', '-c', 'true'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    assert probe.returncode != 0, "/tmp/archive.lock was not held while compression was running"

    t.join(6)
    try:
        os.unlink(CONTROL_FILE)
    except FileNotFoundError:
        pass
    assert not t.is_alive(), "Locked archive request did not complete"
    assert len(result) == 1 and result[0][0].startswith('SUCCESS'), "Locked request failed"
    assert result[0][1] == oracle_archive(get_expected_critical_records(NOVEL_DATE).encode())

def test_concurrent_requests():
    dates = get_log_dates()
    assert len(dates) > 0, "No log dates found to test"

    results = []

    def worker(date):
        header, payload = send_request(date)
        results.append((date, header, payload))

    threads = []
    for i in range(5):
        date = dates[i % len(dates)]
        t = threading.Thread(target=worker, args=(date,))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    assert len(results) == 5, "Not all threads completed"

    for date, header, payload in results:
        assert header is not None, "Failed to get response in concurrent test"
        assert header.startswith("SUCCESS"), f"Expected SUCCESS in concurrent test, got {header}"

        success, decrypted = decrypt_payload(payload)
        assert success, "Decryption failed in concurrent test"

        expected = get_expected_critical_records(date)
        assert decrypted.decode() == expected, f"Data mismatch for {date} in concurrent test. flock might not be implemented correctly."

def test_request_logging_is_tied_to_requests():
    log_path = '/home/user/server.log'
    before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    missing = '2088-11-29'
    assert not os.path.exists(f'/home/user/logs/app_{missing}.log')

    success_header, _ = send_request(NOVEL_DATE)
    error_header, _ = send_request(missing)
    assert success_header.startswith('SUCCESS')
    assert error_header == 'ERROR NOT_FOUND'

    pattern = re.compile(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] REQUESTED: (\d{4}-\d{2}-\d{2}) - STATUS: (SUCCESS|ERROR)$')
    deadline = time.time() + 3
    appended = ''
    while time.time() < deadline:
        if os.path.exists(log_path):
            with open(log_path, 'r') as f:
                f.seek(before)
                appended = f.read()
        entries = [pattern.match(x) for x in appended.splitlines()]
        pairs = [(m.group(1), m.group(2)) for m in entries if m]
        if (NOVEL_DATE, 'SUCCESS') in pairs and (missing, 'ERROR') in pairs:
            break
        time.sleep(0.05)

    lines = [line for line in appended.splitlines() if line]
    assert lines, "No log entries were appended for actual requests"
    for line in lines:
        assert pattern.match(line), f"Invalid newly-appended log line format: {line}"
    pairs = [(pattern.match(line).group(1), pattern.match(line).group(2)) for line in lines]
    assert (NOVEL_DATE, 'SUCCESS') in pairs, "Successful request was not logged"
    assert (missing, 'ERROR') in pairs, "Failed request was not logged"

def test_server_log():
    log_path = '/home/user/server.log'
    assert os.path.exists(log_path), f"Server log {log_path} does not exist"

    with open(log_path, 'r') as f:
        content = f.read()

    lines = content.strip().split('\n')
    assert len(lines) > 0, "Server log is empty"

    pattern = re.compile(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] REQUESTED: \d{4}-\d{2}-\d{2} - STATUS: (SUCCESS|ERROR)$')
    for line in lines:
        assert pattern.match(line), f"Invalid log line format: {line}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
