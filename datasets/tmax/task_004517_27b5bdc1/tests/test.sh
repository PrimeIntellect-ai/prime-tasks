#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

HOST = "127.0.0.1"
PORT = 8888


def query_server(name: str) -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect((HOST, PORT))
            s.sendall(f"{name}\n".encode("utf-8"))
            data = s.recv(1024)
            return data.decode("utf-8").strip()
    except ConnectionRefusedError:
        pytest.fail("Server is not listening on 127.0.0.1:8888. Did you leave it running in the background?")
    except socket.timeout:
        pytest.fail(f"Server timed out when querying for {name}.")
    except Exception as e:
        pytest.fail(f"Unexpected error communicating with server: {e}")


def test_bob_subordinates():
    response = query_server("Bob")
    assert response == "10", f"Expected 10 for Bob, got {response}. Ensure you are bypassing the corrupted index and correctly summing transitive subordinates."


def test_alice_subordinates():
    response = query_server("Alice")
    assert response == "17", f"Expected 17 for Alice, got {response}. Ensure you are bypassing the corrupted index and correctly summing transitive subordinates."


def test_frank_subordinates():
    response = query_server("Frank")
    assert response == "2", f"Expected 2 for Frank, got {response}."


def test_dave_subordinates():
    response = query_server("Dave")
    assert response == "1", f"Expected 1 for Dave, got {response}."


def listener_pid():
    wanted = f"{PORT:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    for procdir in Path("/proc").iterdir():
        if not procdir.name.isdigit():
            continue
        try:
            for fd in (procdir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(procdir.name)
        except OSError:
            continue
    return None


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if listener_pid() is None:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def wait_for_listener(proc, timeout=6.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pid() is not None:
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.1)
    return listener_pid() is not None


def extract_hierarchy():
    text = subprocess.check_output(
        ["tesseract", "/app/org_chart.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    edges = re.findall(r"([A-Za-z][A-Za-z0-9_]*)\s*,\s*([A-Za-z][A-Za-z0-9_]*)", text)
    assert edges, "Could not derive the organizational hierarchy from /app/org_chart.png"
    children = {}
    people = set()
    for manager, employee in edges:
        children.setdefault(manager, []).append(employee)
        people.update((manager, employee))
    return children, people


def expected_totals(children, people):
    with sqlite3.connect("/app/audit.db") as db:
        rows = db.execute(
            "SELECT username, COUNT(*) FROM access_logs NOT INDEXED GROUP BY username"
        ).fetchall()
    own = dict(rows)

    def total(name):
        seen = set()
        stack = [name]
        answer = 0
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            answer += own.get(current, 0)
            stack.extend(children.get(current, ()))
        return answer

    return {name: total(name) for name in people}, own


def source_builds(output_dir):
    roots = [Path("/app"), Path("/home"), Path("/root"), Path("/workspace")]
    sources = []
    for root in roots:
        if root.exists():
            sources.extend(p for p in root.rglob("*.c") if p.is_file())
    sources = sorted(set(sources))
    assert sources, "No C source file was left for the submitted server"

    groups = [(p.parent, [p]) for p in sources]
    for directory in sorted({p.parent for p in sources}):
        group = [p for p in sources if p.parent == directory]
        if len(group) > 1:
            groups.append((directory, group))

    builds = []
    for index, (cwd, files) in enumerate(groups):
        output = Path(output_dir) / f"server_{index}"
        command = ["gcc", "-O2", "-o", str(output), *map(str, files), "-lsqlite3", "-lm"]
        result = subprocess.run(
            command,
            cwd=str(cwd),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        if result.returncode == 0:
            builds.append((output, cwd))
    assert builds, "The submitted C source could not be compiled"
    return builds


def test_compiled_c_server_uses_live_evidence():
    children, people = extract_hierarchy()
    backup = "/tmp/audit.db.verifier-backup"
    shutil.copy2("/app/audit.db", backup)
    stop_listener()

    outsider = "VerifierUser_" + os.urandom(6).hex()
    try:
        with sqlite3.connect("/app/audit.db") as db:
            next_time = db.execute("SELECT COALESCE(MAX(access_time), 0) + 1000 FROM access_logs").fetchone()[0]
            for name in sorted(people):
                for _ in range(random.SystemRandom().randint(2, 7)):
                    db.execute(
                        "INSERT INTO access_logs(username, access_time) VALUES (?, ?)",
                        (name, next_time),
                    )
                    next_time += 1
            outsider_count = random.SystemRandom().randint(3, 9)
            for _ in range(outsider_count):
                db.execute(
                    "INSERT INTO access_logs(username, access_time) VALUES (?, ?)",
                    (outsider, next_time),
                )
                next_time += 1
            db.commit()

        expected, own = expected_totals(children, people)
        expected[outsider] = own[outsider]

        with tempfile.TemporaryDirectory(prefix="c-server-build-") as build_dir:
            builds = source_builds(build_dir)
            failures = []
            for executable, cwd in builds:
                stop_listener()
                proc = subprocess.Popen(
                    [str(executable)],
                    cwd=str(cwd),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                try:
                    if not wait_for_listener(proc):
                        failures.append(f"{executable.name} did not listen on port 8888")
                        continue
                    names = list(expected)
                    random.SystemRandom().shuffle(names)
                    mismatches = []
                    for name in names:
                        response = query_server(name)
                        if response != str(expected[name]):
                            mismatches.append(f"{name}: expected {expected[name]}, got {response!r}")
                    if not mismatches:
                        return
                    failures.append(f"{executable.name}: " + "; ".join(mismatches))
                finally:
                    stop_listener()
                    if proc.poll() is None:
                        proc.kill()
                    try:
                        proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        proc.kill()

        pytest.fail("No compiled submitted C server handled randomized database contents correctly. " + " | ".join(failures))
    finally:
        stop_listener()
        shutil.copy2(backup, "/app/audit.db")
        try:
            os.unlink(backup)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
