#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/validbench.go
package main

import (
    "bufio"
    "fmt"
    "io"
    "net"
    "net/http"
    "os"
    "sync/atomic"
    "time"
)

func main() {
    if len(os.Args) != 4 {
        os.Exit(2)
    }
    expected, err := os.ReadFile(os.Args[3])
    if err != nil {
        os.Exit(2)
    }

    addr := os.Args[1] + ":" + os.Args[2]
    requestBytes := []byte("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    request, _ := http.NewRequest("GET", "http://localhost/", nil)
    start := time.Now()
    duration := 5 * time.Second
    done := make(chan struct{}, 100)
    var valid uint64
    var invalid uint64

    for i := 0; i < 100; i++ {
        go func() {
            for time.Since(start) < duration {
                conn, err := net.DialTimeout("tcp", addr, time.Second)
                if err != nil {
                    time.Sleep(5 * time.Millisecond)
                    continue
                }
                _ = conn.SetDeadline(time.Now().Add(time.Second))
                if _, err = conn.Write(requestBytes); err != nil {
                    atomic.AddUint64(&invalid, 1)
                    conn.Close()
                    continue
                }

                response, err := http.ReadResponse(bufio.NewReader(conn), request)
                if err != nil {
                    atomic.AddUint64(&invalid, 1)
                    conn.Close()
                    continue
                }
                body, bodyErr := io.ReadAll(response.Body)
                response.Body.Close()
                conn.Close()

                if bodyErr == nil && response.ProtoMajor == 1 && response.ProtoMinor == 1 && response.StatusCode == 200 && string(body) == string(expected) {
                    atomic.AddUint64(&valid, 1)
                } else {
                    atomic.AddUint64(&invalid, 1)
                }
            }
            done <- struct{}{}
        }()
    }

    for i := 0; i < 100; i++ {
        <-done
    }
    elapsed := time.Since(start).Seconds()
    rps := float64(atomic.LoadUint64(&valid)) / elapsed
    bad := atomic.LoadUint64(&invalid)
    fmt.Printf("Valid requests per second: %.2f\nInvalid responses: %d\n", rps, bad)
    if rps < 5000.0 || bad != 0 {
        os.Exit(1)
    }
}
GO_EOF
go build -o /tmp/validbench /tmp/validbench.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import re
import signal
import socket
import subprocess
import tempfile
import time


def run_checked(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )
    return result


def test_directories_and_files():
    certs_dir = "/home/user/certs"
    www_dir = "/home/user/www"

    assert os.path.isdir(certs_dir), f"Directory {certs_dir} does not exist"
    assert os.path.isdir(www_dir), f"Directory {www_dir} does not exist"

    crt_path = os.path.join(certs_dir, "server.crt")
    key_path = os.path.join(certs_dir, "server.key")
    assert os.path.isfile(crt_path), f"File {crt_path} does not exist"
    assert os.path.isfile(key_path), f"File {key_path} does not exist"

    active_crt = os.path.join(certs_dir, "active.crt")
    active_key = os.path.join(certs_dir, "active.key")
    assert os.path.islink(active_crt), f"{active_crt} is not a symlink"
    assert os.path.islink(active_key), f"{active_key} is not a symlink"
    assert os.readlink(active_crt) == "server.crt" or os.path.abspath(os.path.join(certs_dir, os.readlink(active_crt))) == os.path.abspath(crt_path), "active.crt does not point to server.crt"
    assert os.readlink(active_key) == "server.key" or os.path.abspath(os.path.join(certs_dir, os.readlink(active_key))) == os.path.abspath(key_path), "active.key does not point to server.key"

    # Confirm that the files are a usable, matching RSA private key and
    # self-signed X.509 certificate, rather than merely existing.
    run_checked(["openssl", "x509", "-in", crt_path, "-noout", "-checkend", "0"])
    run_checked(["openssl", "rsa", "-in", key_path, "-check", "-noout"])
    run_checked(["openssl", "verify", "-CAfile", crt_path, crt_path])
    key_pub = run_checked(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]).stdout
    cert_pub_pem = run_checked(["openssl", "x509", "-in", crt_path, "-pubkey", "-noout"]).stdout
    cert_pub = run_checked(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub_pem
    ).stdout
    assert key_pub == cert_pub, "server.crt and server.key do not contain the same RSA public key"

    target_html = os.path.join(www_dir, "target.html")
    index_html = os.path.join(www_dir, "index.html")
    assert os.path.isfile(target_html), f"File {target_html} does not exist"
    with open(target_html, "r") as f:
        content = f.read()
    assert content == "NETWORK_OK", f"target.html content is '{content}', expected 'NETWORK_OK'"

    assert os.path.islink(index_html), f"{index_html} is not a symlink"
    assert os.readlink(index_html) == "target.html" or os.path.abspath(os.path.join(www_dir, os.readlink(index_html))) == os.path.abspath(target_html), "index.html does not point to target.html"


def test_bashrc_exports():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert re.search(r"^export\s+WWW_PORT=8080", content, re.MULTILINE), "WWW_PORT=8080 export not found in .bashrc"
    assert re.search(r"^export\s+CERT_PATH=/home/user/certs/active\.crt", content, re.MULTILINE), "CERT_PATH export not found in .bashrc"


def assert_http_response():
    sock = socket.create_connection(("localhost", 8080), timeout=2)
    try:
        sock.settimeout(2)
        sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        response = http.client.HTTPResponse(sock)
        response.begin()
        body = response.read()
        assert response.version == 11, f"Expected HTTP/1.1, got version {response.version}"
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        with open("/home/user/www/index.html", "rb") as f:
            expected = f.read()
        assert body == expected, f"Response body was {body!r}, expected {expected!r}"
        assert sock.recv(1) == b"", "Server did not close the connection after its response"
    finally:
        sock.close()


def stop_server(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)


def start_server(path):
    proc = subprocess.Popen([path], start_new_session=True)
    time.sleep(1)
    assert proc.poll() is None, f"Server {path} exited before accepting requests"
    return proc


def test_server_performance():
    server_path = "/home/user/server"
    source_path = "/home/user/server.c"
    assert os.path.isfile(source_path), f"C source {source_path} does not exist"
    assert os.path.getsize(source_path) > 0, f"C source {source_path} is empty"
    assert os.path.isfile(server_path), f"Server binary {server_path} does not exist"
    assert os.access(server_path, os.X_OK), f"Server binary {server_path} is not executable"
    with open(server_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Server is not a compiled ELF executable"

    # Execute the submitted artifact and verify an actual HTTP response.
    server_proc = start_server(server_path)
    try:
        assert_http_response()

        # Preserve the original benchmark assertion.
        bench_out = subprocess.check_output(["/app/bench", "localhost", "8080"], text=True)
        match = re.search(r"Requests per second:\s+([0-9.]+)", bench_out)
        assert match, f"Metric extraction failed. Output was: {bench_out}"
        rps = float(match.group(1))
        assert rps >= 5000.0, f"Server performance too low. Achieved {rps} RPS, expected >= 5000.0"

        # Count only complete, valid HTTP/1.1 200 responses with the required body.
        valid = subprocess.run(
            ["/tmp/validbench", "localhost", "8080", "/home/user/www/index.html"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert valid.returncode == 0, (
            "Valid-response benchmark failed.\n"
            f"stdout: {valid.stdout}\nstderr: {valid.stderr}"
        )
    finally:
        stop_server(server_proc)

    # Compile and exercise server.c independently so the required source is a
    # functioning implementation rather than an unrelated placeholder.
    fd, rebuilt_path = tempfile.mkstemp(prefix="rebuilt-server-", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt_path)
    try:
        compiled = subprocess.run(
            ["gcc", "-O3", "-pthread", source_path, "-o", rebuilt_path],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert compiled.returncode == 0, f"server.c did not compile:\n{compiled.stderr}"
        rebuilt_proc = start_server(rebuilt_path)
        try:
            assert_http_response()
            valid = subprocess.run(
                ["/tmp/validbench", "localhost", "8080", "/home/user/www/index.html"],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            assert valid.returncode == 0, (
                "Server rebuilt from server.c failed the valid-response benchmark.\n"
                f"stdout: {valid.stdout}\nstderr: {valid.stderr}"
            )
        finally:
            stop_server(rebuilt_proc)
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
