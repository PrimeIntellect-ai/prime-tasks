#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier can exclusively exercise the submitted client against a
# controlled implementation of the vulnerable service.
pkill -9 -x service_c 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import queue
import re
import secrets
import socket
import subprocess
import threading
import time

INVESTIGATE_PATH = "/home/user/investigate.py"
FLAG_PATH = "/home/user/flag.txt"
PORT = 13337
BACKDOOR_MARKERS = (b'"algo":"none"', b'"algo": "none"', b'algo:none')


def run_probe(response_flag):
    results = queue.Queue()
    ready = threading.Event()

    def serve_once():
        server = None
        try:
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            deadline = time.time() + 3
            while True:
                try:
                    server.bind(("127.0.0.1", PORT))
                    break
                except OSError:
                    if time.time() >= deadline:
                        raise
                    time.sleep(0.05)
            server.listen(1)
            server.settimeout(8)
            ready.set()

            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                payload = conn.recv(4096)
                exploited = any(marker in payload for marker in BACKDOOR_MARKERS)
                if exploited:
                    conn.sendall((response_flag + "\n").encode())
                else:
                    conn.sendall(b"Access Denied\n")
                results.put((payload, exploited, None))
        except Exception as exc:
            results.put((b"", False, repr(exc)))
            ready.set()
        finally:
            if server is not None:
                server.close()

    if os.path.lexists(FLAG_PATH):
        os.unlink(FLAG_PATH)

    thread = threading.Thread(target=serve_once, daemon=True)
    thread.start()
    assert ready.wait(4), "Controlled service did not become ready."

    completed = subprocess.run(
        ["python3", INVESTIGATE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    thread.join(timeout=9)
    assert not thread.is_alive(), "investigate.py did not contact the service."

    payload, exploited, server_error = results.get_nowait()
    assert server_error is None, f"Controlled service failed: {server_error}"
    assert completed.returncode == 0, (
        f"investigate.py exited with {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert payload, "investigate.py made no usable TCP request."
    assert exploited, f"investigate.py did not send the backdoor payload: {payload!r}"
    assert os.path.isfile(FLAG_PATH), f"Flag file {FLAG_PATH} is missing after execution."
    with open(FLAG_PATH, "r") as f:
        assert f.read().strip() == response_flag, (
            "investigate.py did not save the flag returned by the service."
        )


def test_investigation_script_executes_and_exploits_service():
    assert os.path.isfile(INVESTIGATE_PATH), (
        f"Investigation script {INVESTIGATE_PATH} is missing."
    )

    # A randomized response prevents a script that merely writes the known flag
    # from passing without retrieving the service response.
    random_flag = f"FLAG{{verification_{secrets.token_hex(12)}}}"
    run_probe(random_flag)

    # Leave the required final flag in place and retain the original assertion.
    run_probe("FLAG{jwt_alg_none_c_binary_byp4ss}")


def test_flag_file_exists_and_correct():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"Flag file {flag_path} is missing."

    with open(flag_path, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG{jwt_alg_none_c_binary_byp4ss}"
    assert content == expected_flag, f"Flag file content is incorrect. Expected {expected_flag}, but found: {content}"


def test_firewall_script_exists_and_correct():
    script_path = "/home/user/firewall.sh"
    assert os.path.isfile(script_path), f"Firewall script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read().strip()

    # Retain the original correctness check.
    pattern = r"iptables\s+-A\s+INPUT\s+-p\s+tcp\s+(?:--dport|--destination-port)\s+13337\s+-j\s+DROP"
    assert re.search(pattern, content), f"Firewall script does not contain the correct iptables command. Found: {content}"

    # Blank lines, comments, and an optional shebang are non-commands. Exactly
    # one executable command must remain, and it must be the required rule.
    command_lines = [
        line.strip()
        for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert len(command_lines) == 1, (
        f"Firewall script must contain exactly one command; found {len(command_lines)}: {command_lines}"
    )
    assert re.fullmatch(pattern, command_lines[0]), (
        f"The single firewall command is not exactly the required rule: {command_lines[0]}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
