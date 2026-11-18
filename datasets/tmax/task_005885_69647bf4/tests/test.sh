#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import pathlib
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/workspace"
SCHEDULER_C_PATH = "/home/user/workspace/scheduler.c"
LIBSCHEDULER_SO_PATH = "/home/user/workspace/libscheduler.so"
APP_PATH = "/home/user/workspace/app.py"
FINAL_SCHEDULE_JSON_PATH = "/home/user/workspace/final_schedule.json"


def request_schedule(payload, timeout=5):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/schedule",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, json.loads(body)


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc in pathlib.Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc.name))
        except OSError:
            continue

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
    time.sleep(0.4)
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass


def start_app():
    kill_port_8080()
    proc = subprocess.Popen(
        ["python3", APP_PATH],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"app.py exited before listening (status {proc.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                return proc
        except OSError:
            time.sleep(0.1)
    pytest.fail("app.py did not listen on 127.0.0.1:8080")


def test_c_code_fixed():
    """Test that the C code has been modified to fix the three bugs."""
    assert os.path.exists(SCHEDULER_C_PATH), f"File missing: {SCHEDULER_C_PATH}"

    with open(SCHEDULER_C_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "malloc(strlen(input))" not in content.replace(" ", ""), "Bug 1 (Off-by-one in malloc) is not fixed."
    assert "char name[10]" not in content, "Bug 2 (Buffer overflow with char name[10]) is not fixed."
    assert "free(" in content, "Bug 3 (Memory leak) is not fixed. Missing free() call."


def test_c_implementation_is_memory_safe_for_required_inputs(tmp_path):
    """Compile the submitted source with ASan and exercise all three repaired paths."""
    harness = tmp_path / "harness.c"
    executable = tmp_path / "scheduler_asan"
    harness.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
char* solve_schedule(const char* input);

int main(void) {
    const char *inputs[] = {
        "A,1;",
        "DesignSystemArchitecture,15;ImplementFFI,8;WriteTests,4;",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,7;B,9;C,2;"
    };
    const char *expected[] = {
        "A:0;",
        "DesignSystemArchitecture:0;ImplementFFI:15;WriteTests:23;",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:0;B:7;C:16;"
    };
    for (int i = 0; i < 3; i++) {
        char *result = solve_schedule(inputs[i]);
        if (result == NULL || strcmp(result, expected[i]) != 0) {
            fprintf(stderr, "unexpected result for case %d: %s\n", i,
                    result == NULL ? "(null)" : result);
            free(result);
            return 2;
        }
        free(result);
    }
    return 0;
}
''')
    build = subprocess.run(
        ["gcc", "-O0", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
         SCHEDULER_C_PATH, str(harness), "-o", str(executable)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert build.returncode == 0, f"scheduler.c failed to compile with ASan:\n{build.stderr}"
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    run = subprocess.run(
        [str(executable)], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    )
    assert run.returncode == 0, f"C implementation failed memory-safety/behavior checks:\n{run.stderr}"


def test_shared_library_compiled():
    """Test that the shared library was compiled."""
    assert os.path.exists(LIBSCHEDULER_SO_PATH), f"Shared library missing: {LIBSCHEDULER_SO_PATH}"
    assert os.path.isfile(LIBSCHEDULER_SO_PATH), f"Expected a file: {LIBSCHEDULER_SO_PATH}"


def test_shared_library_executes_general_schedules():
    """Load the submitted shared object and derive expected answers from varied inputs."""
    with open(LIBSCHEDULER_SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libscheduler.so is not an ELF shared library"

    lib = ctypes.CDLL(LIBSCHEDULER_SO_PATH)
    assert hasattr(lib, "solve_schedule"), "Shared library does not export solve_schedule"
    solve = lib.solve_schedule
    solve.argtypes = [ctypes.c_char_p]
    solve.restype = ctypes.c_void_p
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]
    libc.free.restype = None

    nonce = f"N{os.getpid()}{time.time_ns()}"
    cases = [
        [(nonce[:30], 3)],
        [(f"{nonce[:18]}A{i}", duration) for i, duration in enumerate((11, 2, 17, 5, 9))],
        [("Z" * 30, 6), ("tail", 13)],
    ]
    for tasks in cases:
        encoded = "".join(f"{name},{duration};" for name, duration in tasks).encode()
        ptr = solve(encoded)
        assert ptr, "solve_schedule returned NULL"
        try:
            actual = ctypes.string_at(ptr).decode("utf-8")
        finally:
            libc.free(ptr)
        current = 0
        expected_parts = []
        for name, duration in tasks:
            expected_parts.append(f"{name}:{current};")
            current += duration
        assert actual == "".join(expected_parts)


def test_final_schedule_json():
    """Test that the final_schedule.json contains the expected output."""
    assert os.path.exists(FINAL_SCHEDULE_JSON_PATH), f"File missing: {FINAL_SCHEDULE_JSON_PATH}"
    with open(FINAL_SCHEDULE_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Invalid JSON in final_schedule.json")

    expected = [
        {"name": "DesignSystemArchitecture", "start": 0},
        {"name": "ImplementFFI", "start": 15},
        {"name": "WriteTests", "start": 23},
    ]
    assert data == expected, f"Data mismatch in final_schedule.json. Got: {data}"


def test_web_service_running_and_correct():
    """Preserve the original live-service check."""
    payload = [
        {"name": "TaskA", "duration": 10},
        {"name": "TaskB", "duration": 20},
    ]
    try:
        status, resp_data = request_schedule(payload)
        assert status == 200, f"Expected status 200, got {status}"
        expected_resp = [
            {"name": "TaskA", "start": 0},
            {"name": "TaskB", "start": 10},
        ]
        assert resp_data == expected_resp, f"Service returned incorrect schedule. Got: {resp_data}"
    except urllib.error.URLError as e:
        pytest.fail(f"Web service is not reachable or failed: {e}")
    except json.JSONDecodeError:
        pytest.fail("Web service did not return valid JSON.")


def test_app_declares_ctypes_interface():
    assert os.path.isfile(APP_PATH), f"File missing: {APP_PATH}"
    source = pathlib.Path(APP_PATH).read_text()
    ast.parse(source)
    assert "ctypes" in source, "app.py must use ctypes"
    assert "argtypes" in source, "app.py must set solve_schedule.argtypes"
    assert "restype" in source, "app.py must set solve_schedule.restype"
    assert "free" in source, "app.py must free the malloced C result"


def test_service_really_serializes_and_calls_the_shared_library(tmp_path):
    """Replace the library temporarily with a probe whose output cannot be hardcoded."""
    probe_c = tmp_path / "probe.c"
    probe_so = tmp_path / "probe.so"
    probe_c.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* solve_schedule(const char* input) {
    char *copy = malloc(strlen(input) + 1);
    char *result = malloc(4096);
    if (!copy || !result) { free(copy); free(result); return NULL; }
    strcpy(copy, input);
    result[0] = '\0';
    int index = 0;
    char *save = NULL;
    for (char *token = strtok_r(copy, ";", &save); token; token = strtok_r(NULL, ";", &save)) {
        char name[31];
        int duration;
        if (sscanf(token, "%30[^,],%d", name, &duration) != 2) {
            free(copy); free(result); return NULL;
        }
        char part[128];
        int marker = duration * 37 + (++index) * 101;
        snprintf(part, sizeof(part), "%s:%d;", name, marker);
        strcat(result, part);
    }
    free(copy);
    return result;
}
''')
    built = subprocess.run(
        ["gcc", "-shared", "-fPIC", str(probe_c), "-o", str(probe_so)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert built.returncode == 0, built.stderr

    backup = tmp_path / "original_libscheduler.so"
    shutil.copy2(LIBSCHEDULER_SO_PATH, backup)
    probe_proc = None
    try:
        shutil.copy2(probe_so, LIBSCHEDULER_SO_PATH)
        probe_proc = start_app()
        nonce = str(time.time_ns())[-10:]
        payload = [
            {"name": f"Probe{nonce}A", "duration": 4},
            {"name": f"Probe{nonce}B", "duration": 19},
            {"name": f"Probe{nonce}C", "duration": 7},
        ]
        status, actual = request_schedule(payload)
        expected = [
            {"name": item["name"], "start": item["duration"] * 37 + (i + 1) * 101}
            for i, item in enumerate(payload)
        ]
        assert status == 200
        assert actual == expected, (
            "The service did not serialize through and deserialize from solve_schedule; "
            f"got {actual}, expected probe output {expected}"
        )
    finally:
        kill_port_8080()
        shutil.copy2(backup, LIBSCHEDULER_SO_PATH)
        # Leave the required real service running with the submitted library.
        start_app()

    nonce = str(time.time_ns())[-9:]
    payload = [
        {"name": f"Final{nonce}X", "duration": 12},
        {"name": f"Final{nonce}Y", "duration": 3},
        {"name": f"Final{nonce}Z", "duration": 21},
    ]
    status, actual = request_schedule(payload)
    assert status == 200
    assert actual == [
        {"name": payload[0]["name"], "start": 0},
        {"name": payload[1]["name"], "start": 12},
        {"name": payload[2]["name"], "start": 15},
    ]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
