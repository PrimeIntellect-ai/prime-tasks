#!/bin/bash
mkdir -p /logs/verifier

CSV_BACKUP=/tmp/transactions.csv.verifier-backup
SCORER_BACKUP=/tmp/prop_scorer.verifier-backup
SECRET_FILE=/tmp/prop_scorer.verifier-secret
LOG_FILE=/tmp/prop_scorer.verifier-log

cleanup() {
    if [ -f "$CSV_BACKUP" ]; then
        cp -p "$CSV_BACKUP" /home/user/data/transactions.csv
    fi
    if [ -f "$SCORER_BACKUP" ]; then
        cp -p "$SCORER_BACKUP" /app/prop_scorer
    fi
    rm -f "$CSV_BACKUP" "$SCORER_BACKUP" "$SECRET_FILE" "$LOG_FILE"
}
trap cleanup EXIT

if ! cp -p /home/user/data/transactions.csv "$CSV_BACKUP" || ! cp -p /app/prop_scorer "$SCORER_BACKUP"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import random
import socket
import stat
import subprocess

import pytest

HOST = "127.0.0.1"
PORT = 8080
CSV_PATH = "/home/user/data/transactions.csv"
SCORER_PATH = "/app/prop_scorer"
SECRET_FILE = "/tmp/prop_scorer.verifier-secret"
LOG_FILE = "/tmp/prop_scorer.verifier-log"


def send_request(payload):
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as s:
            s.settimeout(5)
            s.sendall(payload.encode("utf-8"))
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks).decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect or communicate with the server at {HOST}:{PORT}. Error: {exc}")


def assert_response(response, node, score):
    assert response, "Received empty response from the server"
    assert response.endswith("\n"), f"Response must end with a newline: {response!r}"
    assert response.count("\n") == 1, f"Response must contain exactly one JSON line: {response!r}"
    try:
        data = json.loads(response.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response}")

    assert "node" in data, "Response JSON missing 'node' key"
    assert "score" in data, "Response JSON missing 'score' key"
    assert set(data) == {"node", "score"}, f"Response JSON has incorrect schema: {data}"
    assert type(data["node"]) is int, f"node must be an integer: {data}"
    assert type(data["score"]) is int, f"score must be an integer: {data}"
    assert data["node"] == node, f"Expected node {node}, got {data['node']}"
    assert data["score"] == score, f"Expected score {score} for node {node}, got {data['score']}"


def listener_is_elf():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address_hex, port_hex = local_address.split(":")
            if address_hex == "0100007F" and int(port_hex, 16) == PORT and state == "0A":
                inodes.add(inode)

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        owns_socket = False
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owns_socket = True
                break
        if owns_socket:
            try:
                with open(f"/proc/{pid}/exe", "rb") as executable:
                    return executable.read(4) == b"\x7fELF"
            except OSError:
                pass
    return False


def test_cpp_artifact_and_compiled_listener():
    assert os.path.isfile("/home/user/server.cpp"), "/home/user/server.cpp does not exist"
    assert os.path.getsize("/home/user/server.cpp") > 0, "/home/user/server.cpp is empty"
    result = subprocess.run(
        ["g++", "-std=c++17", "-fsyntax-only", "/home/user/server.cpp"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"server.cpp is not valid C++: {result.stderr}"
    assert listener_is_elf(), "The process listening on 127.0.0.1:8080 is not a compiled executable"


def test_tcp_server_node_101():
    response = send_request("101\n")
    assert_response(response, 101, 367)


def test_tcp_server_node_102():
    response = send_request("102\n")
    assert_response(response, 102, 334)


def rolling_metric(rows, node):
    amounts = [amount for source, timestamp, amount in sorted(rows, key=lambda r: r[1]) if source == node]
    return max(sum(amounts[start:start + 3]) for start in range(len(amounts)))


def test_runtime_generated_csv_and_scorer_invocation():
    rng = random.SystemRandom()
    nodes = rng.sample(range(300, 900), 4)
    rows = []
    tx_id = 1
    for node in nodes:
        base_time = rng.randrange(10000, 90000)
        for offset in rng.sample(range(1, 1000), rng.randrange(5, 8)):
            rows.append((node, base_time + offset, rng.randrange(10, 901), tx_id))
            tx_id += 1
    rng.shuffle(rows)

    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["tx_id", "source_node", "target_node", "timestamp", "amount"])
        for source, timestamp, amount, current_tx in rows:
            writer.writerow([current_tx, source, rng.randrange(900, 1500), timestamp, amount])

    secret = rng.randrange(100000, 900000)
    with open(SECRET_FILE, "w", encoding="ascii") as f:
        f.write(str(secret))
    open(LOG_FILE, "w").close()

    wrapper = '''#!/bin/bash
if [ "$#" -ne 2 ]; then exit 1; fi
printf '%s %s\\n' "$1" "$2" >> /tmp/prop_scorer.verifier-log
secret=$(cat /tmp/prop_scorer.verifier-secret) || exit 1
node=$1
metric=$2
score=$(( (node * 43 + metric * 97 + secret) % 100000 ))
printf '[SUCCESS] Evaluation complete. Risk Metric: %d\\n' "$score"
'''
    with open(SCORER_PATH, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(SCORER_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    expected_calls = []
    for node in nodes:
        metric = rolling_metric([(r[0], r[1], r[2]) for r in rows], node)
        expected_score = (node * 43 + metric * 97 + secret) % 100000
        assert_response(send_request(f"{node}\n"), node, expected_score)
        expected_calls.append(f"{node} {metric}")

    with open(LOG_FILE, "r", encoding="utf-8") as f:
        actual_calls = [line.strip() for line in f if line.strip()]
    assert collections.Counter(actual_calls) == collections.Counter(expected_calls), (
        f"The server did not invoke /app/prop_scorer exactly once with each dynamically "
        f"computed node and rolling metric. Expected {expected_calls}, got {actual_calls}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
