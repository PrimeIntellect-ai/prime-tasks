#!/bin/bash
mkdir -p /logs/verifier
reward=0

if (
    set -e

    # Recreate the original project state so the submitted script must perform
    # the repairs and build itself during this verification run.
    pkill -f '[t]arget/debug/ws_grpc_proxy' 2>/dev/null || true
    rm -rf /home/user/ws_grpc_proxy
    rm -f /home/user/ws_test.log
    mkdir -p /home/user/ws_grpc_proxy/c_ext
    mkdir -p /home/user/ws_grpc_proxy/proto
    mkdir -p /home/user/ws_grpc_proxy/src

    cat > /home/user/ws_grpc_proxy/c_ext/validator.c <<'EOF'
#include <string.h>

void validate_token(const char* input) {
    char buf[32];
    strcpy(buf, input);
}
EOF

    cat > /home/user/ws_grpc_proxy/proto/service.proto <<'EOF'
syntax = "proto2";

message ProxyRequest {
    string payload = 1;
}
EOF

    cat > /home/user/ws_grpc_proxy/Cargo.toml <<'EOF'
[package]
name = "ws_grpc_proxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }

[build-dependencies]
cc = "1.0"
EOF

    cat > /home/user/ws_grpc_proxy/build.rs <<'EOF'
fn main() {
    cc::Build::new()
        .file("c_ext/validator.c")
        .flag("-Werror=stringop-overflow")
        .compile("validator");
}
EOF

    cat > /home/user/ws_grpc_proxy/src/main.rs <<'EOF'
use std::net::TcpListener;
use std::io::{Read, Write};

extern "C" {
    fn validate_token(input: *const std::ffi::c_char);
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buf = [0; 1024];
        stream.read(&mut buf).unwrap();

        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                        Upgrade: websocket\r\n\
                        Connection: Upgrade\r\n\
                        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n";
        stream.write(response.as_bytes()).unwrap();
    }
}
EOF

    chmod -R 777 /home/user/ws_grpc_proxy

    # Execute the requested artifact against the pristine broken project.
    timeout 300 /bin/bash -x /home/user/fix_and_test.sh > /tmp/fix_and_test.trace 2>&1

    # Stop the script's background instance so the built artifact can also be
    # launched and exercised independently below.
    pkill -f '[t]arget/debug/ws_grpc_proxy' 2>/dev/null || true
    sleep 1

    cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import re
import socket
import stat
import subprocess
import time


def test_script_exists_and_executable():
    script_path = "/home/user/fix_and_test.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_c_file_patched():
    c_file_path = "/home/user/ws_grpc_proxy/c_ext/validator.c"
    assert os.path.isfile(c_file_path), f"C file {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "strncpy" in content, "The C file was not patched to use strncpy."
    assert "strcpy" not in content, "The unsafe strcpy call is still in the C file."
    safe_patch = re.compile(
        r"strncpy\s*\(\s*buf\s*,\s*input\s*,\s*31\s*\)\s*;"
        r"\s*buf\s*\[\s*31\s*\]\s*=\s*'\\0'\s*;"
    )
    assert safe_patch.search(content), "The required bounded copy and explicit null termination are missing."


def test_proto_file_patched():
    proto_file_path = "/home/user/ws_grpc_proxy/proto/service.proto"
    assert os.path.isfile(proto_file_path), f"Protobuf file {proto_file_path} is missing."

    with open(proto_file_path, "r") as f:
        content = f.read()

    assert 'syntax = "proto3";' in content, "The Protobuf file was not patched to use proto3."
    assert 'proto2' not in content, "The proto2 syntax is still in the Protobuf file."


def test_project_built():
    binary_path = "/home/user/ws_grpc_proxy/target/debug/ws_grpc_proxy"
    assert os.path.isfile(binary_path), f"The project binary {binary_path} was not built. Did 'cargo build' run successfully?"
    assert os.access(binary_path, os.X_OK), "The built project artifact is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The project artifact is not an ELF binary."


def test_ws_test_log():
    log_path = "/home/user/ws_test.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did the script run curl and save the output?"

    with open(log_path, "r", errors="replace") as f:
        content = f.read()

    assert "HTTP/1.1 101 Switching Protocols" in content, "The ws_test.log does not contain the expected WebSocket upgrade response."
    lowered = content.lower()
    assert "upgrade: websocket" in lowered, "The log does not contain the WebSocket Upgrade response header."
    assert "connection: upgrade" in lowered, "The log does not contain the Connection upgrade response header."


def test_built_binary_serves_websocket_upgrade():
    binary_path = "/home/user/ws_grpc_proxy/target/debug/ws_grpc_proxy"
    proc = subprocess.Popen(
        [binary_path],
        cwd="/home/user/ws_grpc_proxy",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        sock = None
        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace")
                raise AssertionError(f"Built binary exited before accepting connections: {stderr}")
            try:
                sock = socket.create_connection(("127.0.0.1", 8080), timeout=1)
                break
            except OSError:
                time.sleep(0.1)

        assert sock is not None, "Built binary did not bind to 127.0.0.1:8080."
        with sock:
            request = (
                "GET /ws HTTP/1.1\r\n"
                "Host: 127.0.0.1:8080\r\n"
                "Connection: Upgrade\r\n"
                "Upgrade: websocket\r\n"
                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            )
            sock.sendall(request.encode("ascii"))
            response = b""
            while b"\r\n\r\n" not in response:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk

        text = response.decode("iso-8859-1")
        assert text.startswith("HTTP/1.1 101 Switching Protocols"), text
        assert "upgrade: websocket" in text.lower()
        assert "connection: upgrade" in text.lower()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
