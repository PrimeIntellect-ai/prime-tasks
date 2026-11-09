#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import re
import secrets
import signal
import socket
import subprocess
import time
import pytest

SCRIPT_PATH = "/home/user/server.sh"
HOST = "127.0.0.1"
PORT = 9000


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_existing_service():
    pids = listening_pids(PORT)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_pids(PORT) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listening_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_service(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            if s.connect_ex((HOST, PORT)) == 0:
                return
        time.sleep(0.05)
    pytest.fail("Failed to connect to port 9000 after starting server.sh")


def send_and_receive(host, port, message):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3.0)
        s.connect((host, port))
        s.sendall(message.encode("utf-8"))
        data = bytearray()
        while b"\n" not in data:
            chunk = s.recv(1024)
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > 4096:
                break
        return data.decode("utf-8").strip()


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def make_expression(rng):
    stack = []
    tokens = []
    numbers_left = rng.randrange(3, 8)
    while numbers_left or len(stack) > 1:
        if numbers_left and (len(stack) < 2 or rng.randrange(3) != 0):
            value = rng.randrange(-50, 51)
            tokens.append(str(value))
            stack.append(value)
            numbers_left -= 1
            continue

        b = stack.pop()
        a = stack.pop()
        op = rng.choice(["+", "-", "*", "/"])
        if op == "/" and b == 0:
            op = rng.choice(["+", "-", "*"])
        if op == "+":
            value = a + b
        elif op == "-":
            value = a - b
        elif op == "*":
            value = a * b
        else:
            value = trunc_div(a, b)
        # Keep generated values within a conservative Bash integer range.
        if abs(value) > 1000000000:
            op = "+"
            value = a + b
        tokens.append(op)
        stack.append(value)
    return " ".join(tokens) + "\n", f"RESULT: {stack[0]}"


def test_leak_report():
    report_path = "/home/user/leak_report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist."
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == "1024", f"Expected leak report to contain '1024', but found '{content}'."
    assert re.fullmatch(r"[0-9]+", content), "Leak report must contain only an integer."

    run = subprocess.run(
        ["valgrind", "--leak-check=full", "/app/v1_calc", "10", "5", "+"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
        timeout=15,
    )
    match = re.search(r"definitely lost:\s*([0-9,]+) bytes", run.stderr)
    assert match, f"Could not derive the definitely-lost byte count from valgrind output: {run.stderr}"
    measured = match.group(1).replace(",", "")
    assert content == measured, f"Leak report says {content}, but valgrind measured {measured}."


def test_server_sh_exists():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", errors="strict") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!\s*(?:(?:/usr)?/bin/bash|/usr/bin/env(?:\s+-S)?\s+bash)(?:\s|$)", first_line), \
        "server.sh must be a Bash script with a Bash shebang."
    syntax = subprocess.run(["/bin/bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"server.sh is not valid Bash: {syntax.stderr}"
    assert re.search(r"\$\(\(|\(\(|(?:^|[;&|[:space:]])let(?:[[:space:]]|$)", source), \
        "server.sh does not contain Bash integer arithmetic."
    assert "/app/v1_calc" not in source, "The network service must not invoke the legacy calculator."
    forbidden = re.compile(
        r"(?:^|[;&|()[:space:]])(?:/[^[:space:];|()]+/)?"
        r"(?:python(?:[0-9.]*)?|perl|ruby|node(?:js)?|php|lua|awk|gawk|mawk|bc|dc)"
        r"(?:[[:space:]]|$)",
        re.MULTILINE,
    )
    assert not forbidden.search(source), "The RPN interpreter must be implemented in Bash, not delegated to another language or calculator."


def test_network_service():
    stop_existing_service()
    proc = subprocess.Popen(
        [SCRIPT_PATH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_service()

        owners = listening_pids(PORT)
        assert owners, "No process owns the listening socket on port 9000."
        allowed_listener_exes = {"/usr/bin/socat", "/usr/bin/nc.openbsd", "/bin/bash", "/usr/bin/bash"}
        for pid in owners:
            try:
                exe = os.path.realpath(f"/proc/{pid}/exe")
            except OSError:
                continue
            assert exe in allowed_listener_exes, f"Unexpected non-Bash/network listener executable: {exe}"

        # Preserve the original fixed checks.
        test_cases = [
            ("10 5 +\n", "RESULT: 15"),
            ("3 4 * 2 -\n", "RESULT: 10"),
            ("10 0 /\n", "ERROR: DIV0"),
            ("100 5 / 4 *\n", "RESULT: 80"),
        ]
        for payload, expected in test_cases:
            response = send_and_receive(HOST, PORT, payload)
            assert response == expected, f"Sent '{payload.strip()}', expected '{expected}', but got '{response}'"

        # Generate unpredictable, independently evaluated expressions.
        rng = secrets.SystemRandom()
        generated = [make_expression(rng) for _ in range(36)]
        for _ in range(6):
            numerator = rng.randrange(-100000, 100001)
            generated.append((f"{numerator} 0 /\n", "ERROR: DIV0"))

        # Exercise many simultaneous connections as well as arbitrary expressions.
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            futures = [pool.submit(send_and_receive, HOST, PORT, payload) for payload, _ in generated]
            for (payload, expected), future in zip(generated, futures):
                try:
                    response = future.result(timeout=5)
                except Exception as exc:
                    pytest.fail(f"Concurrent network interaction failed for '{payload.strip()}': {exc}")
                assert response == expected, \
                    f"Sent generated expression '{payload.strip()}', expected '{expected}', but got '{response}'"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        stop_existing_service()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
