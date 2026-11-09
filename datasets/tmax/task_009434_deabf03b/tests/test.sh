#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import signal
import subprocess
import time

import pytest
import requests

API_SERVER_DIR = "/home/user/api_server"
LOG_FILE = os.path.join(API_SERVER_DIR, "status_codes.log")
MAKEFILE = os.path.join(API_SERVER_DIR, "Makefile")
SERVER_EXEC = os.path.join(API_SERVER_DIR, "server")
EXPECTED = "200,200,200,429,429,429,429,429"
PORT_HEX = "1F90"


def listening_socket_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    if state == "0A" and local_address.rsplit(":", 1)[-1].upper() == PORT_HEX:
                        inodes.add(fields[9])
        except OSError:
            pass
    return inodes


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return result
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def server_pids():
    pids = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            target = os.readlink(f"/proc/{name}/exe")
        except OSError:
            continue
        if target == SERVER_EXEC or target == SERVER_EXEC + " (deleted)":
            pids.append(int(name))
    return pids


def pid_is_listening(pid):
    return bool(listening_socket_inodes() & pid_socket_inodes(pid))


def stop_existing_servers():
    pids = server_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_status_codes_log_exists():
    assert os.path.isfile(LOG_FILE), f"The log file {LOG_FILE} was not found."


def test_status_codes_log_content():
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, (
        f"The contents of {LOG_FILE} did not match the expected status codes.\n"
        f"Expected: {EXPECTED}\nGot:      {content}"
    )


def test_server_executable_exists():
    assert os.path.isfile(SERVER_EXEC), (
        f"The server executable {SERVER_EXEC} does not exist. Did you successfully run 'make'?"
    )
    assert os.access(SERVER_EXEC, os.X_OK), f"The file {SERVER_EXEC} is not executable."


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"The Makefile {MAKEFILE} was not found."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    has_math = "-lm" in content
    has_pthread = "-lpthread" in content or "-pthread" in content
    assert has_math, "The Makefile does not contain the '-lm' flag required for math library linking."
    assert has_pthread, "The Makefile does not contain the '-lpthread' or '-pthread' flag required for threading."


def test_real_build_running_server_and_eight_requests():
    running = [pid for pid in server_pids() if pid_is_listening(pid)]
    assert running, "The submitted ./server was not running and listening on port 8080."

    stop_existing_servers()
    proc = None
    try:
        clean = subprocess.run(
            ["make", "clean"], cwd=API_SERVER_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert clean.returncode == 0, f"'make clean' failed:\n{clean.stdout}"

        for artifact in (SERVER_EXEC, os.path.join(API_SERVER_DIR, "main.o"),
                         os.path.join(API_SERVER_DIR, "rate_limiter.o")):
            try:
                os.remove(artifact)
            except FileNotFoundError:
                pass

        build = subprocess.run(
            ["make", "server"], cwd=API_SERVER_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert build.returncode == 0, f"Running 'make server' failed:\n{build.stdout}"
        assert os.path.isfile(SERVER_EXEC) and os.access(SERVER_EXEC, os.X_OK), \
            "make did not create an executable server"
        with open(SERVER_EXEC, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The built server is not an ELF executable"

        dry = subprocess.run(
            ["make", "-nB", "server"], cwd=API_SERVER_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert dry.returncode == 0, f"Could not inspect the Makefile recipes:\n{dry.stdout}"
        link_commands = []
        for line in dry.stdout.splitlines():
            try:
                tokens = shlex.split(line, comments=True)
            except ValueError:
                continue
            if not tokens:
                continue
            compiler_used = any(os.path.basename(t) in ("gcc", "cc", "clang") for t in tokens)
            outputs_server = any(t == "-oserver" for t in tokens)
            outputs_server |= any(
                tokens[i] == "-o" and i + 1 < len(tokens) and os.path.basename(tokens[i + 1]) == "server"
                for i in range(len(tokens))
            )
            if compiler_used and outputs_server:
                link_commands.append(tokens)
        assert link_commands, "No compiler link recipe producing server was found in the Makefile"
        assert any("-lm" in cmd for cmd in link_commands), \
            "The effective server link command does not pass -lm"
        assert any(("-lpthread" in cmd or "-pthread" in cmd) for cmd in link_commands), \
            "The effective server link command does not pass -lpthread or -pthread"

        proc = subprocess.Popen(
            [SERVER_EXEC], cwd=API_SERVER_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        deadline = time.time() + 5
        while time.time() < deadline:
            assert proc.poll() is None, "The freshly built server exited before listening"
            if pid_is_listening(proc.pid):
                break
            time.sleep(0.05)
        else:
            pytest.fail("The freshly built server did not listen on port 8080")

        observed = []
        for _ in range(8):
            response = requests.get("http://127.0.0.1:8080/api/data", timeout=3)
            observed.append(str(response.status_code))
        observed_content = ",".join(observed)

        assert observed_content == EXPECTED, (
            f"Eight sequential requests returned {observed_content}; expected {EXPECTED}"
        )
        with open(LOG_FILE, "r") as f:
            logged_content = f.read().strip()
        assert logged_content == observed_content, \
            "status_codes.log does not match the eight statuses observed from the built server"
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
