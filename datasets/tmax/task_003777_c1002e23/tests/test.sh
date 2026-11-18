#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import json
import math
import os
import re
import secrets
import signal
import socket
import subprocess
import time

import pytest

APP = "/app"
URI = "ws://127.0.0.1:8765"


def kill_port_8765():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == "223D" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    if not inodes:
        return

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
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
                        os.kill(int(pid), signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    break
        except OSError:
            pass
    time.sleep(0.5)


def wait_for_server(proc, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"/app/run.sh exited early with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8765), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("Could not connect to WebSocket server at 127.0.0.1:8765")


def start_server():
    proc = subprocess.Popen(
        ["/app/run.sh"],
        cwd=APP,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server(proc)
    return proc


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    kill_port_8765()


def clean_make():
    lib = os.path.join(APP, "libcore.so")
    try:
        os.unlink(lib)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["make", "-C", APP], text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(lib), "make did not produce /app/libcore.so"


@pytest.fixture(scope="session")
def project():
    lib_path = os.path.join(APP, "libcore.so")
    run_path = os.path.join(APP, "run.sh")
    make_path = os.path.join(APP, "Makefile")
    core_path = os.path.join(APP, "core.c")

    # Preserve the original final-state assertions before rebuilding anything.
    assert os.path.isfile(lib_path), "/app/libcore.so is missing. The C library was not compiled."
    assert os.path.isfile(run_path), "/app/run.sh is missing."
    assert os.access(run_path, os.X_OK), "/app/run.sh is not executable."

    make_text = open(make_path, encoding="utf-8").read()
    assert "-fPIC" in make_text, "Makefile does not compile position-independent code (-fPIC)."
    assert "-shared" in make_text, "Makefile does not create a shared object (-shared)."
    assert "-lm" in make_text, "Makefile does not link against the math library (-lm)."
    run_text = open(run_path, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bmake\b", run_text), "/app/run.sh does not run make."

    core_backup = open(core_path, "rb").read()
    clean_make()

    header = subprocess.run(
        ["readelf", "-h", lib_path], text=True, capture_output=True, timeout=10
    )
    assert header.returncode == 0 and re.search(r"Type:\s+DYN", header.stdout), \
        "/app/libcore.so is not a valid ELF shared object."
    dynamic = subprocess.run(
        ["readelf", "-d", lib_path], text=True, capture_output=True, timeout=10
    )
    assert dynamic.returncode == 0 and re.search(r"NEEDED.*libm\.so", dynamic.stdout), \
        "/app/libcore.so is not dynamically linked to libm."

    library = ctypes.CDLL(lib_path)
    function = library.process_value
    function.argtypes = [ctypes.c_double] * 4
    function.restype = ctypes.c_double
    for x in (-1.25, 0.0, 2.375):
        expected = 7 * math.sin(x) + 22 * math.cos(x) + 81 * math.exp(-x)
        assert math.isclose(function(7, 22, 81, x), expected, rel_tol=1e-11, abs_tol=1e-11)

    kill_port_8765()
    proc = start_server()
    state = {"proc": proc, "core_backup": core_backup}
    try:
        yield state
    finally:
        stop_server(state.get("proc"))
        with open(core_path, "wb") as f:
            f.write(core_backup)
        try:
            clean_make()
        except Exception:
            pass


def test_libcore_so_exists(project):
    assert os.path.isfile("/app/libcore.so"), "/app/libcore.so is missing. The C library was not compiled."


def test_run_sh_exists_and_executable(project):
    assert os.path.isfile("/app/run.sh"), "/app/run.sh is missing."
    assert os.access("/app/run.sh", os.X_OK), "/app/run.sh is not executable."


@pytest.mark.asyncio
async def test_websocket_server(project):
    import websockets

    xs = [1.5] + [secrets.SystemRandom().uniform(-1.75, 3.25) for _ in range(5)]
    async with websockets.connect(URI, ping_timeout=5) as websocket:
        for x in xs:
            await websocket.send(json.dumps({"token": "7_22_81", "x": x}))
            response_str = await asyncio.wait_for(websocket.recv(), timeout=5.0)
            response = json.loads(response_str)
            assert "result" in response, f"Expected 'result' in response, got: {response}"
            expected = 7 * math.sin(x) + 22 * math.cos(x) + 81 * math.exp(-x)
            assert math.isclose(response["result"], expected, rel_tol=1e-8, abs_tol=1e-8), \
                f"Expected result approx {expected}, got {response['result']}"


@pytest.mark.asyncio
async def test_websocket_server_invalid_token(project):
    import websockets

    async with websockets.connect(URI, ping_timeout=5) as websocket:
        await websocket.send(json.dumps({"token": "wrong_token", "x": 1.5}))
        try:
            response_str = await asyncio.wait_for(websocket.recv(), timeout=2.0)
            try:
                response = json.loads(response_str)
                assert "result" not in response, \
                    "Server returned a result for an invalid token instead of dropping or erroring."
            except json.JSONDecodeError:
                pass
        except websockets.exceptions.ConnectionClosed:
            pass
        except asyncio.TimeoutError:
            pass


@pytest.mark.asyncio
async def test_server_invokes_rebuilt_library_via_ffi(project):
    import websockets

    # Replace core.c only during this test with a verifier-generated transform.
    # Since its constants are generated after the agent has finished, a server
    # that hardcodes the known formula cannot predict the responses.
    stop_server(project["proc"])
    project["proc"] = None

    scale = secrets.SystemRandom().uniform(31.0, 79.0)
    bias = secrets.SystemRandom().uniform(101.0, 307.0)
    probe_source = f'''double process_value(double a, double b, double c, double x) {{
    return (a * 0.125) + (b * 0.25) + (c * 0.5) + (x * {scale:.17g}) + {bias:.17g};
}}
'''
    with open("/app/core.c", "w", encoding="utf-8") as f:
        f.write(probe_source)
    try:
        os.unlink("/app/libcore.so")
    except FileNotFoundError:
        pass

    proc = start_server()
    project["proc"] = proc
    try:
        xs = [secrets.SystemRandom().uniform(-4.0, 4.0) for _ in range(4)]
        async with websockets.connect(URI, ping_timeout=5) as websocket:
            for x in xs:
                await websocket.send(json.dumps({"token": "7_22_81", "x": x}))
                response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5.0))
                expected = 7 * 0.125 + 22 * 0.25 + 81 * 0.5 + x * scale + bias
                assert "result" in response
                assert math.isclose(response["result"], expected, rel_tol=1e-10, abs_tol=1e-9), \
                    "Server response did not come from the verifier-generated libcore.so implementation."
    finally:
        stop_server(project["proc"])
        project["proc"] = None
        with open("/app/core.c", "wb") as f:
            f.write(project["core_backup"])
        clean_make()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
