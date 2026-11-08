#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import signal
import socket
import struct
import subprocess
import time

import pytest

BINARY = "/home/user/project/bin/server"
SRC_DIR = "/home/user/project/src"
REBUILT = "/tmp/verifier-rebuilt-server"


def test_binary_exists_and_executable():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Executable {binary_path} not found."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."


def test_binary_linking_rpath():
    binary_path = BINARY
    # Run ldd to check if libsolver.so is found without LD_LIBRARY_PATH
    env = os.environ.copy()
    if "LD_LIBRARY_PATH" in env:
        del env["LD_LIBRARY_PATH"]

    result = subprocess.run(
        ["ldd", binary_path],
        capture_output=True,
        text=True,
        env=env
    )
    assert result.returncode == 0, f"ldd failed on {binary_path}"

    # Check that libsolver.so is resolved (does not say "not found")
    found_libsolver = False
    for line in result.stdout.splitlines():
        if "libsolver.so" in line:
            found_libsolver = True
            assert "not found" not in line, "libsolver.so is 'not found' by ldd. Rpath/Runpath is likely missing or incorrect."
            break

    assert found_libsolver, "libsolver.so is not linked in the final binary."


def test_hub_go_concurrency_fixes():
    hub_go_path = "/home/user/project/src/hub.go"
    assert os.path.isfile(hub_go_path), f"Source file {hub_go_path} is missing."

    with open(hub_go_path, 'r') as f:
        content = f.read()

    assert "sync" in content, "The 'sync' package is not imported in hub.go."
    assert "Mutex" in content, "No Mutex or RWMutex found in hub.go."
    assert "Lock()" in content, "Mutex Lock() not found in hub.go."
    assert "Unlock()" in content, "Mutex Unlock() not found in hub.go."


def test_main_go_cgo_directives():
    main_go_path = "/home/user/project/src/main.go"
    assert os.path.isfile(main_go_path), f"Source file {main_go_path} is missing."

    with open(main_go_path, 'r') as f:
        content = f.read()

    # Check for library path flag
    assert "-L" in content or "LDFLAGS" in content, "LDFLAGS missing in main.go cgo directives."

    # Check for rpath or absolute path link
    has_rpath = "-Wl,-rpath" in content or "-Wl,-R" in content
    has_abs_path = "/home/user/project/lib" in content
    assert has_rpath or has_abs_path, "No rpath directive or absolute library path found in main.go LDFLAGS."


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def test_sources_build_without_library_environment():
    result = subprocess.run(
        ["go", "build", "-o", REBUILT, "."],
        cwd=SRC_DIR,
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Building the submitted sources failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def recv_exact(sock, count):
    data = b""
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise AssertionError("WebSocket connection closed unexpectedly")
        data += part
    return data


def websocket_connect(deadline):
    last_error = None
    while time.time() < deadline:
        sock = None
        try:
            sock = socket.create_connection(("127.0.0.1", 8080), timeout=1)
            sock.settimeout(3)
            key = base64.b64encode(os.urandom(16)).decode("ascii")
            request = (
                "GET /ws HTTP/1.1\r\n"
                "Host: 127.0.0.1:8080\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            )
            sock.sendall(request.encode("ascii"))
            response = b""
            while b"\r\n\r\n" not in response:
                response += sock.recv(4096)
                assert len(response) < 65536, "Oversized WebSocket handshake"
            header = response.split(b"\r\n\r\n", 1)[0].decode("latin1")
            expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()).decode("ascii")
            assert header.startswith("HTTP/1.1 101"), f"WebSocket upgrade failed: {header}"
            assert f"Sec-WebSocket-Accept: {expected}".lower() in header.lower(), "Invalid WebSocket accept response"
            return sock
        except Exception as exc:
            last_error = exc
            if sock is not None:
                sock.close()
            time.sleep(0.1)
    raise AssertionError(f"Server did not accept a WebSocket connection: {last_error}")


def send_text(sock, text):
    payload = text.encode("utf-8")
    mask = os.urandom(4)
    if len(payload) < 126:
        header = bytes((0x81, 0x80 | len(payload)))
    elif len(payload) < 65536:
        header = bytes((0x81, 0xFE)) + struct.pack("!H", len(payload))
    else:
        header = bytes((0x81, 0xFF)) + struct.pack("!Q", len(payload))
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    sock.sendall(header + mask + masked)


def recv_text(sock):
    first, second = recv_exact(sock, 2)
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask = recv_exact(sock, 4) if second & 0x80 else None
    payload = recv_exact(sock, length)
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    assert opcode == 1, f"Expected a text frame, got WebSocket opcode {opcode}"
    return payload.decode("utf-8")


def exercise_server(binary):
    process = subprocess.Popen(
        [binary],
        cwd=SRC_DIR,
        env=clean_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    clients = []
    try:
        deadline = time.time() + 8
        clients.append(websocket_connect(deadline))
        clients.append(websocket_connect(deadline))
        send_text(clients[0], "solve 5")
        assert recv_text(clients[0]) == "solved: 25"
        assert recv_text(clients[1]) == "solved: 25"
        assert process.poll() is None, "Server exited during the WebSocket test"
    finally:
        for client in clients:
            client.close()
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    if not clients:
        pytest.fail(f"Server failed to start. stdout={stdout!r}, stderr={stderr!r}")


def test_submitted_and_rebuilt_servers_have_required_websocket_behavior():
    if not os.path.isfile(REBUILT):
        pytest.fail("Rebuilt server is missing; source build test did not succeed")
    exercise_server(BINARY)
    time.sleep(0.2)
    exercise_server(REBUILT)


def test_hub_is_race_free_under_real_websocket_broadcast_and_mutation():
    test_path = os.path.join(SRC_DIR, "verifier_concurrency_test.go")
    source = r'''package main

import (
    "io"
    "net/http/httptest"
    "strings"
    "sync"
    "testing"

    "golang.org/x/net/websocket"
)

func TestVerifierHubConcurrentBroadcastAndMutation(t *testing.T) {
    accepted := make(chan *websocket.Conn, 16)
    server := httptest.NewServer(websocket.Handler(func(ws *websocket.Conn) {
        accepted <- ws
        _, _ = io.Copy(io.Discard, ws)
    }))
    defer server.Close()

    h := NewHub()
    var clients []*websocket.Conn
    var serverConns []*websocket.Conn
    wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/"
    for i := 0; i < 8; i++ {
        client, err := websocket.Dial(wsURL, "", "http://localhost/")
        if err != nil {
            t.Fatal(err)
        }
        clients = append(clients, client)
        serverConn := <-accepted
        serverConns = append(serverConns, serverConn)
        h.AddClient(serverConn)
        go io.Copy(io.Discard, client)
    }

    var wg sync.WaitGroup
    wg.Add(1)
    go func() {
        defer wg.Done()
        for i := 0; i < 500; i++ {
            h.Broadcast("race-check")
        }
    }()
    for worker := 0; worker < 8; worker++ {
        wg.Add(1)
        go func(worker int) {
            defer wg.Done()
            for i := 0; i < 1000; i++ {
                conn := serverConns[(worker+i)%len(serverConns)]
                h.RemoveClient(conn)
                h.AddClient(conn)
            }
        }(worker)
    }
    wg.Wait()

    for _, conn := range serverConns {
        h.RemoveClient(conn)
    }
    for _, conn := range clients {
        _ = conn.Close()
    }
    for _, conn := range serverConns {
        _ = conn.Close()
    }
}
'''
    assert not os.path.exists(test_path), f"Reserved verifier test path already exists: {test_path}"
    try:
        with open(test_path, "w") as handle:
            handle.write(source)
        result = subprocess.run(
            ["go", "test", "-race", "-count=1", "-run", "^TestVerifierHubConcurrentBroadcastAndMutation$", "."],
            cwd=SRC_DIR,
            env=clean_env(),
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Hub failed concurrent race testing:\n{result.stdout}\n{result.stderr}"
        assert "DATA RACE" not in result.stdout + result.stderr
    finally:
        if os.path.exists(test_path):
            os.unlink(test_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
