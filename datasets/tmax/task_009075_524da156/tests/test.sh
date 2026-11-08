#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import math
import os
import re
import secrets
import subprocess
import tempfile

import websockets

SOURCE = "/home/user/math_utils/mathops.c"
CMAKE = "/home/user/math_utils/CMakeLists.txt"
LIBRARY = "/home/user/math_utils/build/libmathops.so"
RESULT = "/home/user/result.txt"


def expected_newton_sqrt(n):
    x = n
    for _ in range(10):
        x = 0.5 * (x + n / x)
    return x


def load_and_check_library(path, values):
    assert os.path.isfile(path), f"Shared library {path} was not built"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF shared library"

    lib = ctypes.CDLL(path)
    fn = lib.newton_sqrt
    fn.restype = ctypes.c_double
    fn.argtypes = [ctypes.c_double, ctypes.c_int]
    for n in values:
        actual = fn(n, 10)
        expected = expected_newton_sqrt(n)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"newton_sqrt({n}, 10) returned {actual}, expected {expected}"


def random_inputs(count=6):
    return [(secrets.randbelow(2_000_000) + 1) / 997.0 + 0.125 for _ in range(count)]


def test_mathops_c_patched():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "x = 0.5 * (x + n / x);" in content or "x = (x + n / x) / 2" in content or "0.5" in content, \
        "mathops.c does not contain the corrected logic from the patch"


def test_cmake_links_math_library():
    assert os.path.isfile(CMAKE), f"{CMAKE} is missing"
    with open(CMAKE, "r") as f:
        content = f.read()
    assert "target_link_libraries" in content and "m" in content, \
        "CMakeLists.txt does not link the math library (target_link_libraries missing or 'm' not linked)"

    with tempfile.TemporaryDirectory(prefix="verify_math_build_") as build_dir:
        configured = subprocess.run(
            ["cmake", "-S", "/home/user/math_utils", "-B", build_dir],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert configured.returncode == 0, f"Fresh CMake configuration failed:\n{configured.stdout}"

        built = subprocess.run(
            ["cmake", "--build", build_dir, "--verbose"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert built.returncode == 0, f"Fresh CMake build failed:\n{built.stdout}"
        assert re.search(r"(?<!\S)-lm(?!\S)", built.stdout), \
            f"The actual shared-library link command did not link libm:\n{built.stdout}"

        fresh_library = os.path.join(build_dir, "libmathops.so")
        load_and_check_library(fresh_library, random_inputs())


def test_shared_library_built_and_functional():
    load_and_check_library(LIBRARY, random_inputs())


def test_requested_server_process_is_running_with_library_loaded():
    matching = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
            if "ws_server.py" not in cmdline:
                continue
            with open(f"/proc/{entry}/maps", "r", errors="replace") as f:
                maps = f.read()
            if LIBRARY in maps:
                matching.append((entry, cmdline))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    assert matching, "No running ws_server.py process has the built libmathops.so loaded"


async def websocket_exchange(numbers):
    replies = []
    async with websockets.connect("ws://localhost:8765", open_timeout=4, close_timeout=2) as websocket:
        for number in numbers:
            await asyncio.wait_for(websocket.send(str(number)), timeout=2)
            replies.append(await asyncio.wait_for(websocket.recv(), timeout=2))
    return replies


def test_websocket_uses_working_algorithm_on_unpredictable_inputs():
    values = random_inputs()
    replies = asyncio.run(websocket_exchange(values))
    for n, reply in zip(values, replies):
        try:
            actual = float(reply)
        except (TypeError, ValueError):
            raise AssertionError(f"WebSocket returned a non-numeric response for {n}: {reply!r}")
        expected = expected_newton_sqrt(n)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"WebSocket returned {actual} for {n}, expected {expected}"


def test_result_file_correct_and_matches_server_reply():
    assert os.path.isfile(RESULT), f"{RESULT} is missing. The result was not saved."
    with open(RESULT, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()
    assert content, f"{RESULT} is empty"

    try:
        val = float(content)
    except ValueError:
        raise AssertionError(f"Content of {RESULT} is not a valid float: {content}")

    x = 612.0
    for _ in range(10):
        x = 0.5 * (x + 612.0 / x)
    assert abs(val - x) < 1e-5, \
        f"Value in {RESULT} ({val}) does not match the expected computed square root (~{x})"

    reply = asyncio.run(websocket_exchange([612.0]))[0]
    assert raw_content == reply, \
        f"{RESULT} does not contain the exact string currently returned by the WebSocket server"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
