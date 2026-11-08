#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

APP = "/home/user/app"
LIBDIR = APP + "/vendor/libcsched"
LIB_PATH = LIBDIR + "/libcsched.so"
URL = "http://127.0.0.1:8080/schedule"
TOKEN = "Bearer RM-DEPLOY-999"


def run_checked(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=120, **kwargs)
    assert result.returncode == 0, f"Command {' '.join(args)} failed:\n{result.stdout}"
    return result.stdout


def exercise_library(path, cases):
    try:
        lib = ctypes.CDLL(path)
    except OSError as exc:
        pytest.fail(f"Could not load shared library {path}: {exc}")

    try:
        calculate = lib.calculate_schedule
    except AttributeError:
        pytest.fail(f"{path} does not export calculate_schedule")

    calculate.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int,
                          ctypes.POINTER(ctypes.c_int)]
    calculate.restype = ctypes.c_int

    for tasks in cases:
        n = len(tasks)
        in_guard_left = 0x13572468
        in_guard_right = 0x24681357
        out_guard_left = 0x11223344
        out_guard_right = 0x55667788

        in_buf = (ctypes.c_int * (n + 2))()
        out_buf = (ctypes.c_int * (n + 2))()
        in_buf[0] = in_guard_left
        in_buf[n + 1] = in_guard_right
        out_buf[0] = out_guard_left
        out_buf[n + 1] = out_guard_right
        for i, value in enumerate(tasks):
            in_buf[i + 1] = value
            out_buf[i + 1] = -987654321

        in_ptr = ctypes.cast(ctypes.byref(in_buf, ctypes.sizeof(ctypes.c_int)),
                             ctypes.POINTER(ctypes.c_int))
        out_ptr = ctypes.cast(ctypes.byref(out_buf, ctypes.sizeof(ctypes.c_int)),
                              ctypes.POINTER(ctypes.c_int))
        rc = calculate(in_ptr, n, out_ptr)

        expected = []
        current = 0
        for duration in tasks:
            expected.append(current)
            current += duration

        assert rc == 0, f"calculate_schedule returned {rc} for {tasks}"
        assert list(out_buf)[1:n + 1] == expected, (
            f"calculate_schedule produced {list(out_buf)[1:n + 1]}, expected {expected}"
        )
        assert out_buf[0] == out_guard_left and out_buf[n + 1] == out_guard_right, (
            "calculate_schedule wrote outside the output array"
        )
        assert in_buf[0] == in_guard_left and in_buf[n + 1] == in_guard_right, (
            "calculate_schedule modified memory outside the input array"
        )


def http_post(tasks, authorization=None):
    body = json.dumps({"tasks": tasks}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if authorization is not None:
        headers["Authorization"] = authorization
    request = urllib.request.Request(URL, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")
    except OSError as exc:
        pytest.fail(f"Failed to connect to the API at {URL}: {exc}")


def process_socket_inodes(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for entry in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, entry))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            inodes.add(match.group(1))
    return inodes


def listening_tcp_sockets():
    sockets = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                if fields[3] == "0A":
                    sockets.append((table, fields[1], fields[9]))
    return sockets


def test_libcsched_built():
    """Verify that the shared library was successfully built and is functional."""
    assert os.path.isfile(LIB_PATH), (
        f"Shared library {LIB_PATH} does not exist. Did you fix the Makefile and build it?"
    )

    elf_info = run_checked(["readelf", "-h", LIB_PATH])
    assert re.search(r"Type:\s+DYN", elf_info), f"{LIB_PATH} is not an ELF shared object"
    symbols = run_checked(["nm", "-D", LIB_PATH])
    assert re.search(r"\bT\s+calculate_schedule(?:$|@)", symbols, re.MULTILINE), (
        "libcsched.so does not export calculate_schedule"
    )

    cases = [[], [10], [10, 20, 30], [0, 7, -2, 11]]
    exercise_library(LIB_PATH, cases)

    makefile = os.path.join(LIBDIR, "Makefile")
    with open(makefile, "r") as handle:
        make_content = handle.read()
    assert "-fPIC" in make_content, "The Makefile does not compile position-independent code with -fPIC"
    assert "-shared" in make_content, "The Makefile does not link libcsched.so with -shared"

    # Validate that the submitted Makefile can perform a clean build without
    # unlinking the copy currently mapped into the running service.
    with tempfile.TemporaryDirectory() as tempdir:
        build_dir = os.path.join(tempdir, "libcsched")
        shutil.copytree(LIBDIR, build_dir)
        run_checked(["make", "clean"], cwd=build_dir)
        run_checked(["make"], cwd=build_dir)
        rebuilt = os.path.join(build_dir, "libcsched.so")
        assert os.path.isfile(rebuilt), "A clean Makefile build did not produce libcsched.so"
        exercise_library(rebuilt, cases)


def test_c_code_fixed():
    """Verify that the off-by-one bug in schedule.c was fixed."""
    c_file = os.path.join(LIBDIR, "schedule.c")
    assert os.path.isfile(c_file), f"Source file {c_file} is missing."
    with open(c_file, "r") as handle:
        content = handle.read()
    assert "i <= num_tasks" not in content, (
        "The out-of-bounds bug (i <= num_tasks) in schedule.c is still present."
    )


def test_server_pid_exists():
    """Verify that server.pid identifies the running linked Rust server."""
    pid_file = os.path.join(APP, "server.pid")
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing. Did you save the server PID?"
    with open(pid_file, "r") as handle:
        pid_str = handle.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer."

    pid = int(pid_str)
    proc_dir = f"/proc/{pid}"
    assert os.path.isdir(proc_dir), f"PID {pid} from server.pid is not running"
    with open(f"{proc_dir}/stat", "r") as handle:
        state = handle.read().split()[2]
    assert state != "Z", f"PID {pid} is a zombie, not a running server"

    exe_link = os.readlink(f"{proc_dir}/exe")
    assert os.path.basename(exe_link.replace(" (deleted)", "")) == "scheduler-api", (
        f"PID {pid} is not the scheduler-api Rust executable: {exe_link}"
    )

    binary_path = f"{proc_dir}/exe"
    dynamic = run_checked(["readelf", "-d", binary_path])
    assert re.search(r"NEEDED.*\[libcsched\.so\]", dynamic), (
        "The running Rust binary is not dynamically linked to libcsched.so"
    )
    symbols = run_checked(["nm", "-D", binary_path])
    assert re.search(r"\bU\s+calculate_schedule(?:$|@)", symbols, re.MULTILINE), (
        "The running Rust binary has no FFI reference to calculate_schedule"
    )

    with open(f"{proc_dir}/maps", "r") as handle:
        maps = handle.read()
    assert "libcsched.so" in maps, "The running server has not loaded libcsched.so"

    owned = process_socket_inodes(pid)
    listeners = [(table, address) for table, address, inode in listening_tcp_sockets()
                 if inode in owned]
    assert ("/proc/net/tcp", "0100007F:1F90") in listeners, (
        f"PID {pid} is not listening on exactly 127.0.0.1:8080; listeners were {listeners}"
    )
    for table, address in listeners:
        if address.endswith(":1F90"):
            assert table == "/proc/net/tcp" and address == "0100007F:1F90", (
                "The server has an additional non-loopback listener on port 8080"
            )


def test_api_unauthorized():
    """Verify that the API rejects missing and incorrect credentials with 401."""
    status, _ = http_post([10, 20, 30])
    assert status == 401, f"Expected 401 Unauthorized without auth header, got {status}"

    for wrong_value in ("RM-DEPLOY-999", "Bearer wrong", "Bearer RM-DEPLOY-999 ", "bearer RM-DEPLOY-999"):
        status, _ = http_post([10, 20, 30], wrong_value)
        assert status == 401, f"Expected 401 for incorrect Authorization value {wrong_value!r}, got {status}"


def test_api_authorized_and_correct():
    """Exercise the API on unpredictable task lists and derive every expected schedule."""
    # Retain the original known case.
    cases = [[10, 20, 30], [], [5], [0, 4, 0, 9], [-3, 8, 2]]
    rng = random.SystemRandom()
    for _ in range(12):
        cases.append([rng.randint(-500, 500) for _ in range(rng.randint(2, 24))])

    for tasks in cases:
        status, text = http_post(tasks, TOKEN)
        assert status == 200, (
            f"Expected 200 OK for authorized request with {tasks}, got {status}. Response: {text}"
        )
        try:
            data = json.loads(text)
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {text}")
        assert "schedule" in data, f"Response JSON missing 'schedule' key: {data}"

        expected = []
        current = 0
        for duration in tasks:
            expected.append(current)
            current += duration
        assert data["schedule"] == expected, (
            f"Expected schedule {expected} for tasks {tasks}, got {data['schedule']}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
