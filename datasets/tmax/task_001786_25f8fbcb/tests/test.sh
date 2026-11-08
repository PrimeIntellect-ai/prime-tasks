#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import signal
import socket
import subprocess
import time

import pytest

LUA_ROOT = "/app/vendored/lua-5.4.6"
LUA_SRC = LUA_ROOT + "/src"
WORKSPACE = "/home/user/workspace"
SERVER = WORKSPACE + "/lua_server"
PORT = 8888


def run_checked(command, cwd, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(command)}\n{result.stdout}"
    return result.stdout


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def stop_existing_listener(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    if listener_inodes(port):
        for pid in victims:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_start_submission():
    # Actually exercise the repaired vendored build rather than trusting a file
    # named liblua.a.
    run_checked(["make", "clean"], LUA_ROOT)
    run_checked(["make", "linux"], LUA_ROOT)

    archive = LUA_SRC + "/liblua.a"
    assert os.path.isfile(archive), "Lua build did not produce liblua.a"
    assert os.path.getsize(archive) > 0, "liblua.a is empty"
    members = run_checked(["ar", "t", archive], LUA_ROOT)
    assert any(line.endswith(".o") for line in members.splitlines()), "liblua.a is not a populated object archive"
    symbols = run_checked(["nm", "-g", archive], LUA_ROOT)
    for symbol in ("lua_newstate", "lua_pcallk", "lua_tonumberx", "lua_close"):
        assert re.search(rf"\b{re.escape(symbol)}\b", symbols), f"liblua.a lacks {symbol}"

    stop_existing_listener(PORT)
    try:
        os.remove(SERVER)
    except FileNotFoundError:
        pass
    run_checked(["make", "-B", "lua_server"], WORKSPACE)
    assert os.path.isfile(SERVER), "workspace build did not create lua_server"
    assert os.access(SERVER, os.X_OK), "lua_server is not executable"
    with open(SERVER, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "lua_server is not an ELF executable"

    binary_symbols = run_checked(["nm", "-g", SERVER], WORKSPACE)
    assert re.search(r"\blua_(?:p?callk|callk)\b", binary_symbols), "lua_server does not contain Lua execution API symbols"
    assert re.search(r"\blua_(?:tonumberx|tointegerx)\b", binary_symbols), "lua_server does not contain Lua numeric-result API symbols"
    assert re.search(r"\bluaL_(?:loadbufferx|loadfilex|newstate)\b", binary_symbols), "lua_server does not contain Lua auxiliary API symbols"

    proc = subprocess.Popen(
        [SERVER],
        cwd=WORKSPACE,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, f"rebuilt lua_server exited with status {proc.returncode}"
        if listener_inodes(PORT):
            break
        time.sleep(0.05)
    assert listener_inodes(PORT), "rebuilt lua_server did not listen on port 8888"
    return proc


def test_lua_makefile_fixed():
    makefile_path = "/app/vendored/lua-5.4.6/src/Makefile"
    assert os.path.isfile(makefile_path), f"Lua Makefile {makefile_path} is missing"

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-lbrokenmath" not in content, "Makefile still contains the broken flag '-lbrokenmath'"
    assert "-lm" in content, "Makefile does not contain the required math library flag '-lm'"


def test_liblua_built():
    liblua_path = "/app/vendored/lua-5.4.6/src/liblua.a"
    assert os.path.isfile(liblua_path), f"Lua static library {liblua_path} was not built"


def test_workspace_files_exist():
    workspace = "/home/user/workspace"
    assert os.path.isfile(os.path.join(workspace, "server.cpp")), "server.cpp is missing"
    assert os.path.isfile(os.path.join(workspace, "Makefile")), "Makefile in workspace is missing"
    assert os.path.isfile(os.path.join(workspace, "lua_server")), "lua_server executable is missing"
    with open(os.path.join(workspace, "Makefile"), errors="replace") as handle:
        makefile = handle.read()
    assert "/app/vendored/lua-5.4.6/src/liblua.a" in makefile, "workspace Makefile does not link the vendored Lua archive"


def send_raw(message, split=False):
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as sock:
        sock.settimeout(5)
        payload = message.encode("utf-8")
        if split and len(payload) > 2:
            cut = secrets.randbelow(len(payload) - 1) + 1
            sock.sendall(payload[:cut])
            time.sleep(0.02)
            sock.sendall(payload[cut:])
        else:
            sock.sendall(payload)
        data = bytearray()
        while True:
            chunk = sock.recv(1024)
            if not chunk:
                break
            data.extend(chunk)
            assert len(data) < 4096, "server returned an unexpectedly large response"
    return bytes(data)


def assert_numeric_response(expression, expected, split=False):
    data = send_raw(expression + "\n", split=split)
    assert data.endswith(b"\n"), f"response is not newline terminated: {data!r}"
    assert data.count(b"\n") == 1, f"response contains extra lines: {data!r}"
    text = data[:-1].decode("utf-8")
    try:
        actual = float(text)
    except ValueError:
        pytest.fail(f"response is not numeric: {text!r}")
    assert math.isfinite(actual), f"response is not finite: {text!r}"
    assert math.isclose(actual, float(expected), rel_tol=1e-10, abs_tol=1e-10), (
        f"expression {expression!r}: expected {expected}, got {text!r}"
    )


def test_tcp_server_interaction():
    # Preserve the original checks.
    response1 = send_raw("return 17 * 3\n").decode("utf-8").strip()
    assert response1 in ["51", "51.0"], f"Expected 51 or 51.0, but got: {response1}"

    response2 = send_raw("return math.sqrt(144)\n").decode("utf-8").strip()
    assert response2 in ["12", "12.0"], f"Expected 12 or 12.0, but got: {response2}"

    # Unpredictable, Lua-specific requests prevent a connection-order lookup
    # server from satisfying the behavioral test.
    a = secrets.randbelow(9000) + 1000
    b = secrets.randbelow(700) + 11
    c = secrets.randbelow(29) + 2
    assert_numeric_response(f"return ({a} * {b} + {c}) / {c}", (a * b + c) / c, split=True)

    n = secrets.randbelow(80) + 40
    k = secrets.randbelow(8) + 3
    expected_loop = sum(i % k for i in range(1, n + 1))
    assert_numeric_response(
        f"return (function() local s=0; for i=1,{n} do s=s+(i%{k}) end; return s end)()",
        expected_loop,
        split=True,
    )

    x = secrets.randbelow(20000) + 100
    y = secrets.randbelow(65535)
    shift = secrets.randbelow(5) + 1
    assert_numeric_response(f"return (({x} << {shift}) ~ {y}) & 65535", ((x << shift) ^ y) & 65535)

    root = secrets.randbelow(900) + 20
    offset = secrets.randbelow(100) + 1
    assert_numeric_response(f"return math.sqrt({root * root}) + {offset}", root + offset)

    byte_value = secrets.randbelow(26) + 65
    character = chr(byte_value)
    extra = secrets.randbelow(500) + 1
    assert_numeric_response(f'return string.byte("{character}", 1) + {extra}', byte_value + extra)

    count = secrets.randbelow(12) + 4
    values = ",".join(str(secrets.randbelow(1000)) for _ in range(count))
    assert_numeric_response(f"return #{{{values}}}", count)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
