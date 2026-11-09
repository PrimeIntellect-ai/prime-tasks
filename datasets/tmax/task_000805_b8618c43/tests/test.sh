#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time

WORK = "/home/user/token-env"
EXPECTED = "VALIDATION_SUCCESS: 8a9d1c7e6b5f4a3d2c1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c"


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", WORK)
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(cmd)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_qa_report_exists_and_correct():
    report_path = os.path.join(WORK, "qa_report.txt")
    assert os.path.isfile(report_path), f"File not found: {report_path}"
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, (
        f"Content of qa_report.txt is incorrect. Expected '{EXPECTED}', Got '{content}'"
    )


def test_protobuf_generated():
    pb_go = os.path.join(WORK, "auth/service.pb.go")
    grpc_go = os.path.join(WORK, "auth/service_grpc.pb.go")
    assert os.path.isfile(pb_go), f"Protobuf Go file not generated: {pb_go}"
    assert os.path.isfile(grpc_go), f"gRPC Go file not generated: {grpc_go}"


def test_legacy_crypto_fixed():
    c_file = os.path.join(WORK, "legacy_crypto.c")
    assert os.path.isfile(c_file), f"File not found: {c_file}"
    with open(c_file, "r") as f:
        content = f.read()
    assert "malloc(16)" not in content, "legacy_crypto.c still contains the buggy malloc(16)"


def test_makefile_fixed():
    makefile_path = os.path.join(WORK, "Makefile")
    assert os.path.isfile(makefile_path), f"File not found: {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-fPIC" in content or "-shared" in content, (
        "Makefile does not seem to be fixed (missing -fPIC or -shared flags)"
    )


def test_shared_library_exists():
    so_file = os.path.join(WORK, "liblegacy_crypto.so")
    assert os.path.isfile(so_file), f"Shared library not successfully built: {so_file}"


def test_build_memory_safety_and_end_to_end_execution():
    so_file = os.path.join(WORK, "liblegacy_crypto.so")

    # Do not permit a stale or empty artifact to satisfy the build checks.
    if os.path.lexists(so_file):
        os.remove(so_file)
    run(["make", "clean"])
    run(["make"])
    assert os.path.isfile(so_file), "Makefile did not build liblegacy_crypto.so"
    run(["readelf", "-h", so_file])
    symbols = run(["nm", "-D", so_file]).stdout
    assert "validate_token_c" in symbols, "Shared library does not export validate_token_c"

    # Exercise the repaired C code under AddressSanitizer so an undersized
    # replacement allocation cannot pass merely because it happened not to crash.
    harness_path = "/tmp/token_crypto_harness.c"
    harness_bin = "/tmp/token_crypto_harness"
    with open(harness_path, "w") as f:
        f.write(r'''#include <stdlib.h>
#include <string.h>
#include "legacy_crypto.h"
int main(void) {
    const char *expected = "VALIDATION_SUCCESS: 8a9d1c7e6b5f4a3d2c1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c";
    char *valid = validate_token_c("12345678901234567890123456789012");
    if (!valid || strcmp(valid, expected) != 0) return 2;
    free(valid);
    char *invalid = validate_token_c("short");
    if (!invalid || strcmp(invalid, "INVALID") != 0) return 3;
    free(invalid);
    return 0;
}
''')
    run([
        "gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g",
        "-I", WORK, os.path.join(WORK, "legacy_crypto.c"), harness_path,
        "-o", harness_bin,
    ], cwd="/tmp")
    asan_env = os.environ.copy()
    asan_env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    run([harness_bin], cwd="/tmp", env=asan_env)

    # Compilation validates that the generated protobuf and gRPC files are real
    # Go stubs and that the server can link against the rebuilt C library.
    server_bin = "/tmp/token-env-server"
    client_bin = "/tmp/token-env-client"
    run(["go", "build", "-o", server_bin, "server.go"])
    run(["go", "build", "-o", client_bin, "client.go"])

    # Use a verifier-owned generic gRPC caller, rather than trusting client.go's
    # presentation alone, to exercise both valid and invalid requests.
    probe_source = os.path.join(WORK, "verifier_probe_tmp.go")
    probe_bin = "/tmp/token-env-probe"
    with open(probe_source, "w") as f:
        f.write(r'''package main
import (
    "context"
    "fmt"
    "os"
    "time"
    pb "token-env/auth"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)
func call(conn *grpc.ClientConn, token string) (string, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()
    out := new(pb.TokenResponse)
    err := conn.Invoke(ctx, "/auth.AuthService/ValidateToken", &pb.TokenRequest{Token: token}, out)
    return out.GetStatus(), err
}
func main() {
    conn, err := grpc.Dial("127.0.0.1:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(2) }
    defer conn.Close()
    valid, err := call(conn, "12345678901234567890123456789012")
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(3) }
    invalid, err := call(conn, "short")
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(4) }
    fmt.Println(valid)
    fmt.Println(invalid)
}
''')
    try:
        run(["go", "build", "-o", probe_bin, probe_source])
    finally:
        if os.path.exists(probe_source):
            os.remove(probe_source)

    # Stop any agent-left server so the process below must be the one handling
    # the verifier's requests against the freshly rebuilt library.
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/cwd") == WORK:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.5)

    server_env = os.environ.copy()
    server_env["LD_LIBRARY_PATH"] = WORK + (":" + server_env["LD_LIBRARY_PATH"] if server_env.get("LD_LIBRARY_PATH") else "")
    ldd = run(["ldd", so_file]).stdout
    if "libasan" in ldd:
        libasan = run(["gcc", "-print-file-name=libasan.so"]).stdout.strip()
        if os.path.isfile(libasan):
            server_env["LD_PRELOAD"] = libasan

    log = open("/tmp/token-env-server.log", "w+")
    server = subprocess.Popen([server_bin], cwd=WORK, env=server_env, stdout=log, stderr=log)
    try:
        deadline = time.time() + 20
        ready = False
        while time.time() < deadline:
            if server.poll() is not None:
                break
            try:
                with socket.create_connection(("127.0.0.1", 50051), timeout=0.25):
                    ready = True
                    break
            except OSError:
                time.sleep(0.1)
        if not ready:
            log.flush()
            log.seek(0)
            raise AssertionError("Server did not start successfully:\n" + log.read())
        assert server.poll() is None, "The newly built server exited before testing"

        probe = run([probe_bin], cwd=WORK, env=server_env, timeout=15)
        assert probe.stdout.splitlines() == [EXPECTED, "INVALID"], (
            f"Unexpected gRPC responses: {probe.stdout!r}"
        )
        assert server.poll() is None, "Server crashed while handling token requests"

        client = run([client_bin], cwd=WORK, env=server_env, timeout=15)
        assert client.stdout == EXPECTED + "\n", f"Unexpected client output: {client.stdout!r}"
        assert client.stderr == "", f"Successful client emitted errors: {client.stderr!r}"
        with open(os.path.join(WORK, "qa_report.txt"), "rb") as f:
            report_bytes = f.read()
        assert report_bytes == client.stdout.encode(), (
            "qa_report.txt is not exactly the output produced by the successful client run"
        )
        assert server.poll() is None, "Server crashed during the client run"
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        log.close()
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
