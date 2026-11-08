#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import signal
import socket
import string
import subprocess
import threading
import time

PROJECT_DIR = "/home/user/project"
PORT = 8080


def port_is_listening():
    port_hex = f"{PORT:04X}"
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 3 and fields[1].split(":")[-1].upper() == port_hex and fields[3] == "0A":
                        return True
        except OSError:
            pass
    return False


def stop_process_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)


def wait_for_server(proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        if port_is_listening():
            return True
        time.sleep(0.02)
    return False


def test_rust_compilation():
    result = subprocess.run(
        ["cargo", "build"], cwd=PROJECT_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "Cargo build failed. The FFI signature might still be incorrect.\n"
        f"Stderr:\n{result.stderr}"
    )


def test_c_memory_safety_fix():
    transform_c_path = os.path.join(PROJECT_DIR, "lib/transform.c")
    assert os.path.exists(transform_c_path), f"{transform_c_path} is missing."

    with open(transform_c_path) as f:
        content = f.read()

    has_alloc = any(func in content for func in ["malloc", "calloc", "strdup"])
    assert has_alloc, (
        "transform.c does not use dynamic memory allocation (malloc, calloc, or strdup). "
        "The memory safety bug is likely not fixed properly."
    )

    rng = random.SystemRandom()
    values = [
        "",
        "alreadyUPPER",
        "MiXeD123",
        "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(127)),
        "".join(rng.choice(string.ascii_lowercase) for _ in range(900)),
    ]
    cases = "\n".join(
        '    {"%s", "%s"},' % (value, value.upper()) for value in values
    )
    harness = f'''\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char *transform_string(const char *input);
void free_string(char *ptr);

struct test_case {{ const char *input; const char *expected; }};

int main(void) {{
    struct test_case cases[] = {{
{cases}
    }};
    size_t count = sizeof(cases) / sizeof(cases[0]);
    for (int pass = 0; pass < 30; ++pass) {{
        for (size_t i = 0; i < count; ++i) {{
            char *result = transform_string(cases[i].input);
            if (result == NULL || strcmp(result, cases[i].expected) != 0) {{
                fprintf(stderr, "bad transform at pass %d case %zu\\n", pass, i);
                return 2;
            }}
            free_string(result);
        }}
    }}
    return 0;
}}
'''
    harness_path = "/tmp/ffi_harness.c"
    binary_path = "/tmp/ffi_harness"
    with open(harness_path, "w") as f:
        f.write(harness)
    compiled = subprocess.run(
        ["cc", "-std=c11", "-O2", "-Wall", "-Wextra", harness_path, transform_c_path, "-o", binary_path],
        capture_output=True,
        text=True,
    )
    assert compiled.returncode == 0, f"C FFI harness failed to compile:\n{compiled.stderr}"
    exercised = subprocess.run([binary_path], capture_output=True, text=True)
    assert exercised.returncode == 0, (
        "transform_string did not return correct independently-owned memory that "
        f"free_string can repeatedly deallocate.\nStderr:\n{exercised.stderr}"
    )


def test_server_ffi_behavior_on_derived_inputs():
    assert not port_is_listening(), "Port 8080 was unexpectedly occupied before server testing."
    server = subprocess.Popen(
        [os.path.join(PROJECT_DIR, "target/debug/api_server")],
        cwd=PROJECT_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        assert wait_for_server(server), "The compiled API server did not listen on 127.0.0.1:8080."
        rng = random.SystemRandom()
        requests = [
            "MixedCase123",
            "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(23)),
            "".join(rng.choice(string.ascii_lowercase) for _ in range(311)),
        ]
        for value in requests:
            response = subprocess.run(
                ["/usr/bin/curl", "--fail", "--silent", "--show-error", f"http://127.0.0.1:8080/api/transform?text={value}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert response.returncode == 0, f"API request failed for a verifier-generated input: {response.stderr}"
            assert response.stdout == value.upper(), (
                f"API returned {response.stdout!r}; expected the derived value {value.upper()!r}."
            )
    finally:
        stop_process_group(server)


def test_e2e_script_exists_and_executable():
    script_path = os.path.join(PROJECT_DIR, "test_e2e.sh")
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable. Did you forget to run 'chmod +x'?"


def traced_commands(trace):
    commands = []
    for line in trace.splitlines():
        if not line.startswith("+ "):
            continue
        try:
            commands.append(shlex.split(line[2:]))
        except ValueError:
            pass
    return commands


def test_e2e_script_execution_and_result():
    script_path = os.path.join(PROJECT_DIR, "test_e2e.sh")
    result_path = os.path.join(PROJECT_DIR, "e2e_result.txt")
    expected_url = "http://127.0.0.1:8080/api/transform?text=helloworld"

    if os.path.exists(result_path):
        os.remove(result_path)
    assert not port_is_listening(), "Port 8080 was occupied before running test_e2e.sh."

    observed_listener = threading.Event()
    stop_monitor = threading.Event()

    def monitor():
        while not stop_monitor.is_set():
            if port_is_listening():
                observed_listener.set()
            time.sleep(0.001)

    proc = subprocess.Popen(
        ["bash", "-x", script_path],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    watcher = threading.Thread(target=monitor, daemon=True)
    watcher.start()
    timed_out = False
    try:
        try:
            stdout, stderr = proc.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            timed_out = True
            stop_process_group(proc)
            stdout, stderr = proc.communicate()
    finally:
        stop_monitor.set()
        watcher.join(timeout=2)

    left_server_running = port_is_listening()
    if left_server_running or timed_out:
        stop_process_group(proc)
        time.sleep(0.1)

    assert not timed_out, f"test_e2e.sh timed out.\nStdout:\n{stdout}\nStderr:\n{stderr}"
    assert proc.returncode == 0, (
        f"test_e2e.sh failed with exit code {proc.returncode}.\n"
        f"Stdout:\n{stdout}\nStderr:\n{stderr}"
    )

    commands = traced_commands(stderr)
    used_cargo_run = any(
        any(os.path.basename(token) == "cargo" for token in command[:1]) and len(command) >= 2 and command[1] == "run"
        for command in commands
    )
    used_required_curl = any(
        command and os.path.basename(command[0]) == "curl" and expected_url in command
        for command in commands
    )
    assert used_cargo_run, "test_e2e.sh did not execute cargo run."
    assert used_required_curl, f"test_e2e.sh did not invoke curl with the required URL {expected_url}."
    assert observed_listener.is_set(), "test_e2e.sh never started a server listening on 127.0.0.1:8080."
    assert not left_server_running, "test_e2e.sh exited without terminating its background server."

    assert os.path.exists(result_path), f"{result_path} was not created by test_e2e.sh."
    with open(result_path) as f:
        content = f.read().strip()
    assert content == "HELLOWORLD", f"Expected 'HELLOWORLD' in e2e_result.txt, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
