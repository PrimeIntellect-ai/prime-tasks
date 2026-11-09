#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import socket
import stat
import subprocess
import tempfile
import time

import pytest

REPO = "/home/user/math_server"
SOURCE = os.path.join(REPO, "server.cpp")
BINARY = "/tmp/verifier_math_server"
HOST = "127.0.0.1"
PORT = 8080


def jacobsthal(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, b + 2 * a
    return a


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), 15)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.3)


@pytest.fixture(scope="session", autouse=True)
def compiled_server():
    assert os.path.exists(SOURCE), f"Expected {SOURCE} to exist."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Expected {SOURCE} to be a regular source file."

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"server.cpp failed to compile:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    kill_port_8080_listeners()
    proc = subprocess.Popen(
        [BINARY], cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read().decode(errors="replace")
            pytest.fail(f"Compiled server exited before listening: {stderr}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        proc.terminate()
        pytest.fail("Compiled server.cpp did not listen on 127.0.0.1:8080")

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def historical_result(commit, n):
    shown = subprocess.run(
        ["git", "show", f"{commit}:server.cpp"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    ).stdout

    harness = (
        "#define main historical_server_main\n"
        + shown
        + "\n#undef main\n"
        + "int main(int argc, char **argv) {\n"
          "  if (argc != 2) return 2;\n"
          "  std::cout << calculate(std::atoi(argv[1])) << std::endl;\n"
          "  return 0;\n"
          "}\n"
    )
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "historical.cpp")
        exe = os.path.join(td, "historical")
        with open(src, "w") as f:
            f.write(harness)
        build = subprocess.run(
            ["g++", "-std=c++17", "-O0", src, "-o", exe],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert build.returncode == 0, f"Could not inspect historical commit {commit}: {build.stderr}"
        try:
            run = subprocess.run(
                [exe, str(n)], capture_output=True, text=True, timeout=2
            )
        except subprocess.TimeoutExpired:
            return None
        if run.returncode != 0:
            return None
        try:
            return int(run.stdout.strip())
        except ValueError:
            return None


def test_bad_commit_identified():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.exists(bad_commit_file), f"Expected {bad_commit_file} to exist."

    result = subprocess.run(
        ["git", "log", "--reverse", "--format=%H"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    commits = result.stdout.strip().split("\n")
    assert len(commits) >= 4, "Expected at least 4 commits in the repository history."
    expected_bad_commit = commits[2]

    with open(bad_commit_file) as f:
        actual_bad_commit = f.read().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", actual_bad_commit), "Bad commit must be a full 40-character hash."
    assert actual_bad_commit == expected_bad_commit, (
        f"Incorrect bad commit hash in {bad_commit_file}. "
        f"Expected {expected_bad_commit}, got {actual_bad_commit}."
    )

    parent = subprocess.run(
        ["git", "rev-parse", f"{actual_bad_commit}^"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    probes = (5, 10)
    assert all(historical_result(parent, n) == jacobsthal(n) for n in probes), (
        "The parent of the reported commit does not match the oracle formula."
    )
    assert any(historical_result(actual_bad_commit, n) != jacobsthal(n) for n in probes), (
        "The reported commit does not introduce the formula regression."
    )


def recv_line(sock, buffered=b""):
    deadline = time.monotonic() + 3
    while b"\n" not in buffered:
        if time.monotonic() >= deadline:
            raise TimeoutError("Timed out waiting for newline-terminated response")
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Server closed the connection before responding")
        buffered += chunk
    line, buffered = buffered.split(b"\n", 1)
    return line.decode("utf-8").strip(), buffered


def test_tcp_server_responses():
    test_cases = [
        ("5", "11"),
        ("10", "341"),
        ("0", "0"),
        ("1", "1"),
        ("6", "21"),
        ("7", "43"),
    ]

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect((HOST, PORT))
    except Exception as e:
        pytest.fail(f"Failed to connect to the math server at {HOST}:{PORT}: {e}")

    buffered = b""
    try:
        for inp, expected in test_cases:
            s.sendall(f"{inp}\n".encode("utf-8"))
            response, buffered = recv_line(s, buffered)
            assert response == expected, (
                f"Server returned incorrect result for input '{inp}'. "
                f"Expected '{expected}', got '{response}'."
            )
    finally:
        s.close()


def test_dynamic_formula_efficiency_and_persistent_connection():
    # Unpredictable probes prevent a fixed six-answer implementation. n=64 also
    # requires an efficient implementation rather than exponential recursion.
    candidates = [n for n in range(2, 64) if n not in {5, 6, 7, 10}]
    rng = random.SystemRandom()
    values = rng.sample(candidates, 24)
    values.extend([32, 48, 63, 64])
    rng.shuffle(values)

    payload = "".join(f"{n}\n" for n in values).encode("ascii")
    with socket.create_connection((HOST, PORT), timeout=3) as s:
        s.settimeout(3)
        start = time.monotonic()
        s.sendall(payload)
        buffered = b""
        for n in values:
            response, buffered = recv_line(s, buffered)
            expected = str(jacobsthal(n))
            assert response == expected, (
                f"Server returned incorrect result for input {n}: "
                f"expected {expected}, got {response}."
            )
        assert time.monotonic() - start < 3.0, "Server is not efficient for larger inputs."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
