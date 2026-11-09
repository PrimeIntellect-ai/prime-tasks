#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import tempfile
import time
import uuid

import pytest
from scapy.all import Raw, TCP, rdpcap

SERVER_PATH = "/home/user/server.py"
MRE_PATH = "/home/user/mre.js"
REG_PATH = "/home/user/regression_test.py"
PCAP_PATH = "/home/user/incident.pcap"


def poison_from_pcap():
    candidates = []
    for packet in rdpcap(PCAP_PATH):
        if packet.haslayer(TCP) and packet[TCP].dport == 9000 and packet.haslayer(Raw):
            payload = bytes(packet[Raw].load)
            try:
                message = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if message.get("action") == "update_profile" and "user_id" not in message:
                candidates.append(payload)
    assert len(candidates) == 1, "PCAP must contain exactly one update_profile request missing user_id"
    return candidates[0]


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def test_server_fixed():
    """Test that server.py handles the poison pill without crashing and returns the correct error."""
    assert os.path.isfile(SERVER_PATH), "server.py is missing"
    poison = poison_from_pcap()

    proc = subprocess.Popen(["python3", SERVER_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(1)
    try:
        assert proc.poll() is None, "server.py did not remain running"

        with socket.create_connection(("127.0.0.1", 9000), timeout=3) as sock:
            sock.settimeout(3)
            sock.sendall(poison)
            data = sock.recv(1024)
        response = json.loads(data.decode("utf-8"))
        assert response.get("status") == "error", "Expected status: error for poison payload"
        assert response.get("reason") == "bad_request", "Expected reason: bad_request for poison payload"

        with socket.create_connection(("127.0.0.1", 9000), timeout=3) as sock:
            sock.settimeout(3)
            sock.sendall(b'{"action": "ping"}')
            data2 = sock.recv(1024)
        response2 = json.loads(data2.decode("utf-8"))
        assert response2.get("status") == "pong", "Expected status: pong for ping payload"
        assert proc.poll() is None, "Server crashed after handling requests"
    finally:
        stop_process(proc)


def test_mre_js_exists_and_runs():
    """Execute mre.js against a vulnerable server and verify the PCAP payload causes its crash."""
    assert os.path.isfile(MRE_PATH), "mre.js is missing"

    syntax = subprocess.run(["node", "--check", MRE_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"mre.js has syntax errors: {syntax.stderr}"

    expected = poison_from_pcap()
    token = uuid.uuid4().hex
    received_path = f"/tmp/mre_received_{token}"
    ready_path = f"/tmp/mre_ready_{token}"
    fixture_path = f"/tmp/vulnerable_server_{token}.py"
    with open(fixture_path, "w") as fixture:
        fixture.write(f'''import json\nimport socket\n\nserver = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\nserver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\nserver.bind(("127.0.0.1", 9000))\nserver.listen(1)\nopen({ready_path!r}, "w").write("ready")\nconn, _ = server.accept()\ndata = conn.recv(1024)\nopen({received_path!r}, "wb").write(data)\nmsg = json.loads(data.decode("utf-8"))\nif msg.get("action") == "update_profile":\n    user_id = msg["user_id"]\nconn.close()\nserver.close()\n''')

    proc = subprocess.Popen(["python3", fixture_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 3
        while not os.path.exists(ready_path) and time.time() < deadline:
            assert proc.poll() is None, "vulnerable fixture failed to start"
            time.sleep(0.05)
        assert os.path.exists(ready_path), "vulnerable fixture did not listen on port 9000"

        result = subprocess.run(["node", MRE_PATH], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"mre.js failed: {result.stdout}\n{result.stderr}"
        proc.wait(timeout=3)

        assert os.path.isfile(received_path), "mre.js did not connect and send a payload"
        with open(received_path, "rb") as received_file:
            received = received_file.read()
        assert received == expected, "mre.js did not send the exact poison payload found in the PCAP"
        assert proc.returncode != 0, "mre.js did not crash the vulnerable server"
    finally:
        stop_process(proc)
        for path in (received_path, ready_path, fixture_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def run_regression_with_server(server_source, expect_success):
    token = uuid.uuid4().hex
    backup = f"/tmp/server_actual_{token}.py"
    marker = f"/tmp/regression_server_pid_{token}"
    os.replace(SERVER_PATH, backup)
    try:
        source = server_source(backup, marker)
        with open(SERVER_PATH, "w") as server_file:
            server_file.write(source)

        env = os.environ.copy()
        env["VERIFIER_SERVER_MARKER"] = marker
        timed_out = False
        try:
            result = subprocess.run(
                ["python3", REG_PATH], capture_output=True, text=True,
                timeout=10, env=env
            )
            returncode = result.returncode
            output = result.stdout + "\n" + result.stderr
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            returncode = -1
            output = f"timed out: {exc}"

        assert os.path.isfile(marker), "regression_test.py did not start /home/user/server.py as a subprocess"
        with open(marker) as marker_file:
            server_pid = int(marker_file.read().strip())

        time.sleep(0.5)
        cleaned_up = not pid_alive(server_pid)
        if not cleaned_up:
            try:
                os.kill(server_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        assert cleaned_up, "regression_test.py did not clean up its server subprocess"

        if expect_success:
            assert not timed_out and returncode == 0, f"regression_test.py failed: {output}"
        else:
            assert timed_out or returncode != 0, "regression_test.py passed against an intentionally broken server"
    finally:
        try:
            os.unlink(SERVER_PATH)
        except FileNotFoundError:
            pass
        os.replace(backup, SERVER_PATH)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def actual_server_wrapper(backup, marker):
    return f'''import os\nimport runpy\nopen({marker!r}, "w").write(str(os.getpid()))\nrunpy.run_path({backup!r}, run_name="__main__")\n'''


def mutant_server(poison_response, ping_response):
    def make_source(_backup, marker):
        return f'''import json\nimport os\nimport socket\nopen({marker!r}, "w").write(str(os.getpid()))\nserver = socket.socket(socket.AF_INET, socket.SOCK_STREAM)\nserver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\nserver.bind(("127.0.0.1", 9000))\nserver.listen(5)\nwhile True:\n    conn, _ = server.accept()\n    data = conn.recv(1024)\n    msg = json.loads(data.decode("utf-8"))\n    if msg.get("action") == "update_profile":\n        conn.sendall({poison_response!r})\n    elif msg.get("action") == "ping":\n        conn.sendall({ping_response!r})\n    conn.close()\n'''
    return make_source


def test_regression_test_py_exists_and_passes():
    """Run the regression test and mutation-check that it tests both required responses."""
    assert os.path.isfile(REG_PATH), "regression_test.py is missing"

    run_regression_with_server(actual_server_wrapper, expect_success=True)
    run_regression_with_server(
        mutant_server(b'{"status": "updated"}', b'{"status": "pong"}'),
        expect_success=False,
    )
    run_regression_with_server(
        mutant_server(b'{"status": "error", "reason": "bad_request"}', b'{"status": "not_pong"}'),
        expect_success=False,
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
