#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import socket
import string
import subprocess
import time

import pytest

WORKSPACE = "/home/user/minilogd_project"
REPORT_FILE = "/home/user/e2e_report.txt"
E2E_SCRIPT = os.path.join(WORKSPACE, "run_e2e.sh")
TEST_PROTOCOL = os.path.join(WORKSPACE, "test_protocol.c")
TEST_EXECUTABLE = os.path.join(WORKSPACE, "test_protocol")
MAKEFILE = os.path.join(WORKSPACE, "Makefile")


def run_checked(command, timeout=30):
    proc = subprocess.run(
        command,
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert proc.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{proc.stdout.decode(errors='replace')}\n"
        f"stderr:\n{proc.stderr.decode(errors='replace')}"
    )
    return proc


def test_e2e_report():
    assert os.path.isfile(E2E_SCRIPT), f"Orchestration script {E2E_SCRIPT} does not exist."
    if os.path.exists(REPORT_FILE):
        os.unlink(REPORT_FILE)

    proc = subprocess.Popen(
        ["bash", E2E_SCRIPT],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(
            "run_e2e.sh timed out.\n"
            f"stdout:\n{stdout.decode(errors='replace')}\n"
            f"stderr:\n{stderr.decode(errors='replace')}"
        )

    assert proc.returncode == 0, (
        f"run_e2e.sh exited with {proc.returncode}.\n"
        f"stdout:\n{stdout.decode(errors='replace')}\n"
        f"stderr:\n{stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."
    with open(REPORT_FILE, "r") as f:
        content = f.read().strip()
    assert content == "E2E_STATUS: SUCCESS", (
        f"Expected 'E2E_STATUS: SUCCESS' in {REPORT_FILE}, got '{content}'"
    )


def test_test_protocol_exists():
    assert os.path.isfile(TEST_PROTOCOL), f"Unit test file {TEST_PROTOCOL} does not exist."


def test_makefile_has_test_target():
    assert os.path.isfile(MAKEFILE), f"Makefile {MAKEFILE} does not exist."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "test:" in content, "Makefile does not contain a 'test' target."


def test_e2e_script_executable():
    assert os.path.isfile(E2E_SCRIPT), f"Orchestration script {E2E_SCRIPT} does not exist."
    assert os.access(E2E_SCRIPT, os.X_OK), f"Orchestration script {E2E_SCRIPT} is not executable."


def test_make_test_builds_and_runs_unit_test():
    proc = run_checked(["make", "clean", "all", "test"])
    assert os.path.isfile(TEST_EXECUTABLE), "make test did not create the test_protocol executable."
    assert os.access(TEST_EXECUTABLE, os.X_OK), "test_protocol is not executable."

    unit = subprocess.run(
        [TEST_EXECUTABLE],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert unit.returncode == 0, (
        f"test_protocol exited with {unit.returncode}.\n"
        f"stdout:\n{unit.stdout.decode(errors='replace')}\n"
        f"stderr:\n{unit.stderr.decode(errors='replace')}"
    )


def test_parse_message_on_derived_inputs():
    rng = random.SystemRandom()
    payloads = [
        "Hello",
        "",
        "".join(rng.choice(string.ascii_letters + string.digits + "_-.") for _ in range(7)),
        "".join(rng.choice(string.ascii_letters + string.digits + "_-.") for _ in range(63)),
    ]

    cases = "\n".join(
        "    check(%s, %s);" % (json.dumps("MSG:" + payload), json.dumps(payload))
        for payload in payloads
    )
    source = f'''\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "protocol.h"

static void check(const char *raw, const char *expected) {{
    struct ClientMessage msg = {{0, NULL}};
    parse_message(raw, &msg);
    if (msg.type != 1 || msg.payload == NULL || strcmp(msg.payload, expected) != 0) {{
        fprintf(stderr, "bad parse for [%s]\\n", raw);
        free(msg.payload);
        exit(1);
    }}
    free(msg.payload);
}}

int main(void) {{
{cases}
    struct ClientMessage invalid = {{99, (char *)1}};
    parse_message("NOT_A_MESSAGE", &invalid);
    if (invalid.type != 0 || invalid.payload != NULL) return 2;
    return 0;
}}
'''
    harness_source = "/tmp/minilogd_protocol_harness.c"
    harness_binary = "/tmp/minilogd_protocol_harness"
    with open(harness_source, "w") as f:
        f.write(source)

    run_checked([
        "gcc", "-Wall", "-g", "-I", WORKSPACE,
        harness_source, os.path.join(WORKSPACE, "protocol.c"),
        "-o", harness_binary,
    ])
    harness = subprocess.run(
        [harness_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert harness.returncode == 0, (
        f"parse_message failed generated cases.\n"
        f"stdout:\n{harness.stdout.decode(errors='replace')}\n"
        f"stderr:\n{harness.stderr.decode(errors='replace')}"
    )


def test_valgrind_memory_leaks():
    # Preserve the original clean build assertion.
    build_proc = subprocess.run(
        ["make", "clean", "all"],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert build_proc.returncode == 0, f"Failed to build project:\n{build_proc.stderr.decode()}"

    valgrind_cmd = [
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all",
        "--error-exitcode=1",
        "./minilogd",
        "8081",
    ]
    server_proc = subprocess.Popen(
        valgrind_cmd,
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )

    rng = random.SystemRandom()
    generated = [
        "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(n))
        for n in (1, 17, 127)
    ]
    payloads = ["TEST_VALGRIND"] + generated

    try:
        time.sleep(1)
        for payload in payloads:
            with socket.create_connection(("127.0.0.1", 8081), timeout=3) as s:
                s.sendall(("MSG:" + payload + "\n").encode())
            time.sleep(0.05)

        with socket.create_connection(("127.0.0.1", 8081), timeout=3) as s:
            s.sendall(b"QUIT\n")

        stdout, stderr = server_proc.communicate(timeout=10)
    except Exception as exc:
        if server_proc.poll() is None:
            os.killpg(server_proc.pid, signal.SIGKILL)
        stdout, stderr = server_proc.communicate()
        pytest.fail(
            f"Failed to communicate with minilogd: {exc}\n"
            f"stdout:\n{stdout.decode(errors='replace')}\n"
            f"stderr:\n{stderr.decode(errors='replace')}"
        )

    stderr_text = stderr.decode(errors="replace")
    stdout_text = stdout.decode(errors="replace")
    assert server_proc.returncode == 0, (
        f"Valgrind reported errors or leaks (exit code {server_proc.returncode}):\n{stderr_text}"
    )
    assert "in use at exit: 0 bytes in 0 blocks" in stderr_text, (
        f"Valgrind did not report zero outstanding allocations:\n{stderr_text}"
    )
    assert "ERROR SUMMARY: 0 errors" in stderr_text, (
        f"Valgrind did not report a clean error summary:\n{stderr_text}"
    )
    for payload in payloads:
        assert f"Received payload: {payload}" in stdout_text, (
            f"Server did not log generated payload {payload!r}.\nstdout:\n{stdout_text}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
