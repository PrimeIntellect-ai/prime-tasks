#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

REAL_PARSER=""
LAUNCHER_PID=""
TRACE_FILE="/tmp/verifier_parser_trace.jsonl"

kill_port_8000() {
python3 <<'PY' >/dev/null 2>&1
import os
import signal
import time

def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F40") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids

for sig in (signal.SIGTERM, signal.SIGKILL):
    pids = listener_pids()
    if not pids:
        break
    for pid in pids:
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)
PY
}

cleanup() {
    if [ -n "$LAUNCHER_PID" ]; then
        kill -TERM -- "-$LAUNCHER_PID" >/dev/null 2>&1 || true
    fi
    kill_port_8000 || true
    if [ -n "$REAL_PARSER" ] && [ -e "$REAL_PARSER" ]; then
        rm -f /app/log_parser
        mv "$REAL_PARSER" /app/log_parser >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if [ ! -x /app/log_parser ]; then
    exit 0
fi

REAL_PARSER="/tmp/verifier_log_parser.real.$$"
if ! mv /app/log_parser "$REAL_PARSER"; then
    exit 0
fi

cat > /app/log_parser <<EOF
#!/usr/bin/python3
import base64
import fcntl
import json
import subprocess
import sys

REAL_PARSER = "$REAL_PARSER"
TRACE_FILE = "$TRACE_FILE"
data = sys.stdin.buffer.read()
record = {
    "count": len(data.splitlines()),
    "data": base64.b64encode(data).decode("ascii"),
}
with open(TRACE_FILE, "a", encoding="utf-8") as trace:
    fcntl.flock(trace.fileno(), fcntl.LOCK_EX)
    trace.write(json.dumps(record) + "\\n")
    trace.flush()
    fcntl.flock(trace.fileno(), fcntl.LOCK_UN)

result = subprocess.run(
    [REAL_PARSER],
    input=data,
    stdout=sys.stdout.buffer,
    stderr=sys.stderr.buffer,
)
sys.exit(result.returncode)
EOF
chmod 755 /app/log_parser
: > "$TRACE_FILE"
chmod 666 "$TRACE_FILE"

kill_port_8000
setsid bash /home/user/server.sh >/tmp/verifier_server.stdout 2>/tmp/verifier_server.stderr &
LAUNCHER_PID=$!

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import socket
import time

TRACE_FILE = "/tmp/verifier_parser_trace.jsonl"


def test_server_script_exists():
    script_path = "/home/user/server.sh"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."


def exchange(payload):
    host = "127.0.0.1"
    port = 8000
    max_retries = 5
    sock = None
    for i in range(max_retries):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(8.0)
            sock.connect((host, port))
            break
        except ConnectionRefusedError:
            if sock is not None:
                sock.close()
                sock = None
            if i == max_retries - 1:
                assert False, f"Could not connect to {host}:{port}. Is the server running?"
            time.sleep(1)

    try:
        sock.sendall(payload.encode("utf-8"))
        sock.shutdown(socket.SHUT_WR)
        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
        return response.decode("utf-8")
    finally:
        sock.close()


def test_tcp_server_processing():
    payload = """line 1
line 2
line 3
CORRUPT line
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
CORRUPT data
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
"""

    expected_output = """PROCESSED: line 1
PROCESSED: line 2
PROCESSED: line 3
PROCESSED: line 4
PROCESSED: line 5
PROCESSED: line 6
PROCESSED: line 7
PROCESSED: line 8
PROCESSED: line 9
PROCESSED: line 10
PROCESSED: line 11
PROCESSED: line 12
PROCESSED: line 13
PROCESSED: line 14
PROCESSED: line 15
PROCESSED: line 16
PROCESSED: line 17
PROCESSED: line 18
PROCESSED: line 19
PROCESSED: line 20
PROCESSED: line 21
PROCESSED: line 22
PROCESSED: line 23
"""

    response_str = exchange(payload)
    assert response_str == expected_output, (
        f"Server response did not match expected output.\n"
        f"Expected:\n{expected_output}\n"
        f"Got:\n{response_str}"
    )


def test_randomized_input_is_sanitized_and_chunked_through_parser():
    token = "VERIFY_" + secrets.token_hex(12)
    clean_lines = [
        f"{token} item {i} value {secrets.token_hex(5)} !?"
        for i in range(27)
    ]

    wire_lines = []
    corrupt_before = {2, 11, 20}
    for i, line in enumerate(clean_lines):
        if i in corrupt_before:
            wire_lines.append(f"CORRUPT {token} rejected {secrets.token_hex(4)}")
        wire_lines.append(line)
    wire_lines.append(f"discard this CORRUPT {token} tail")

    payload = "".join(line + "\n" for line in wire_lines)
    sanitized = "".join(line + "\n" for line in clean_lines)
    expected = "".join("PROCESSED: " + line + "\n" for line in clean_lines)

    response = exchange(payload)
    assert response == expected, (
        "Server failed on verifier-generated input.\n"
        f"Expected:\n{expected}\nGot:\n{response}"
    )

    records = []
    with open(TRACE_FILE, encoding="utf-8") as trace:
        for raw in trace:
            record = json.loads(raw)
            data = base64.b64decode(record["data"])
            if token.encode() in data:
                records.append((record, data))

    assert records, "The server did not invoke /app/log_parser for the generated request."
    assert len(records) >= 3, "More than 20 clean lines were not split across parser executions."
    assert b"".join(data for _, data in records) == sanitized.encode(), (
        "The bytes fed to /app/log_parser were not exactly the sanitized input in order."
    )
    for record, data in records:
        assert 1 <= record["count"] <= 10, (
            f"A /app/log_parser invocation received {record['count']} lines; maximum is 10."
        )
        assert record["count"] == len(data.splitlines())
        assert b"CORRUPT" not in data, "A CORRUPT line was passed to /app/log_parser."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
