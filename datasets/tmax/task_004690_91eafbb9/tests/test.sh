#!/bin/bash
mkdir -p /logs/verifier

# Stop the setup server if the agent left it running; the verifier supplies its
# own test streams on the required port.
pkill -f '^python3 /home/user/server.py$' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import stat
import subprocess
import threading
import time

import pytest

SOURCE = "/home/user/process.c"
BINARY = "/tmp/submission_process"
OUTPUT = "/home/user/clean_stats.csv"

ORIGINAL_DATA = [
    "1,100,50.0,1024\n",
    "2,101,60.0,1024\n",
    "1,100,50.0,1024\n",
    "3,102,70.0,2048\n",
    "4,103,20.0,2048\n",
    "3,102,70.0,2048\n",
    "4,103,20.0,2048\n",
    "5,104,30.0,1024\n",
    "6,105,40.0,4096\n",
    "7,106,80.0,4096\n",
    "6,105,40.0,4096\n",
    "8,107,15.0,2048\n",
]

ORIGINAL_EXPECTED = [
    "id,rolling_cpu",
    "1,50.00",
    "2,55.00",
    "3,60.00",
    "4,50.00",
    "5,40.00",
    "6,30.00",
    "7,50.00",
    "8,45.00",
]


def read_nonempty_lines():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_output(expected_lines):
    actual_lines = read_nonempty_lines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {OUTPUT}, but got "
        f"{len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}: expected '{expected}', got '{actual}'."
        )


def expected_for(records):
    seen = set()
    window = []
    result = ["id,rolling_cpu"]
    for record in records:
        record_id, _timestamp, cpu, _memory = record.strip().split(",")
        numeric_id = int(record_id)
        if numeric_id in seen:
            continue
        seen.add(numeric_id)
        window.append(float(cpu))
        window = window[-3:]
        result.append(f"{numeric_id},{sum(window) / len(window):.2f}")
    return result


def run_with_server(records):
    payload = "".join(records).encode("ascii")
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 8080))
    listener.listen(1)
    listener.settimeout(5)

    state = {"connected": False, "error": None}

    def serve():
        try:
            conn, _ = listener.accept()
            state["connected"] = True
            with conn:
                # Deliberately split records across TCP writes so the submission
                # must parse a stream rather than assume one recv per CSV row.
                sizes = (1, 7, 2, 13, 4, 9)
                offset = 0
                index = 0
                while offset < len(payload):
                    size = sizes[index % len(sizes)]
                    conn.sendall(payload[offset:offset + size])
                    offset += size
                    index += 1
                    time.sleep(0.002)
        except Exception as exc:
            state["error"] = exc
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        completed = subprocess.run(
            [BINARY],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    finally:
        thread.join(timeout=6)
        try:
            listener.close()
        except OSError:
            pass

    assert not thread.is_alive(), "The test server did not finish."
    assert state["connected"], "The submitted program never connected to TCP port 8080."
    assert state["error"] is None, f"TCP stream failed while serving the program: {state['error']}"
    assert completed.returncode == 0, (
        f"Program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_program_compiles_connects_and_computes_results():
    assert os.path.lexists(SOURCE), f"Required source file {SOURCE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} is not a regular file."

    compiled = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compiled.returncode == 0, f"process.c did not compile:\n{compiled.stderr}"

    # Preserve the original verifier's exact assertions for the setup stream.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_with_server(ORIGINAL_DATA)
    assert_output(ORIGINAL_EXPECTED)

    # Exercise the compiled artifact on a fresh stream whose IDs and CPU values
    # are selected at verification time and whose expected result is derived here.
    base = 10000 + secrets.randbelow(800000)
    cpus = [10 + secrets.randbelow(81) for _ in range(6)]
    unique = [
        f"{base + i},{1700000000 + i},{cpus[i]}.0,{1024 * (i + 1)}\n"
        for i in range(6)
    ]
    dynamic_data = [
        unique[0], unique[1], unique[0], unique[2], unique[3],
        unique[1], unique[4], unique[3], unique[5], unique[5],
    ]

    os.remove(OUTPUT)
    run_with_server(dynamic_data)
    assert_output(expected_for(dynamic_data))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
