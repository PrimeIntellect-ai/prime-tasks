#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import signal
import socket
import subprocess
import time


def run_checked(command, cwd, timeout=300):
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return result


def kill_port_listeners(port):
    wanted_inodes = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                if fields[1].rsplit(":", 1)[-1].upper() == port_hex:
                    wanted_inodes.add(fields[9])

    victims = set()
    for fd_path in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            target = os.readlink(fd_path)
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in wanted_inodes:
            try:
                victims.add(int(fd_path.split("/")[2]))
            except (ValueError, IndexError):
                pass

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.5)


def wait_for_server(process, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert process.poll() is None, "Rust server exited before accepting connections"
        try:
            with socket.create_connection(("127.0.0.1", 50051), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("Rust server did not listen on 127.0.0.1:50051")


def test_final_state_and_live_integration():
    project = "/home/user/project"
    rust_dir = os.path.join(project, "backend_rust")
    cpp_dir = os.path.join(project, "client_cpp")
    build_dir = os.path.join(cpp_dir, "build")
    exe_path = os.path.join(build_dir, "feature_test")
    log_path = os.path.join(project, "test_results.log")
    cmake_path = os.path.join(cpp_dir, "CMakeLists.txt")

    # Preserve the original final-state assertions.
    assert os.path.exists(log_path), (
        f"Log file {log_path} does not exist. Did you run the client and redirect output?"
    )
    with open(log_path, "r") as handle:
        original_log = handle.read()
    assert "FeatureData-778899" in original_log.strip(), (
        f"Expected 'FeatureData-778899' in {log_path}, but got: {original_log.strip()}"
    )

    assert os.path.isdir(rust_dir), f"Directory {rust_dir} does not exist."
    cargo_check = subprocess.run(
        ["cargo", "check"], cwd=rust_dir, capture_output=True, text=True, timeout=300
    )
    assert cargo_check.returncode == 0, (
        "Rust server still does not compile. Cargo check failed:\n" + cargo_check.stderr
    )

    assert os.path.exists(exe_path), (
        f"Compiled C++ client {exe_path} does not exist. Did you build it?"
    )
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."

    assert os.path.exists(cmake_path), f"{cmake_path} is missing."
    with open(cmake_path, "r") as handle:
        cmake_content = handle.read()
    assert "target_link_libraries" in cmake_content, (
        "CMakeLists.txt is still missing target_link_libraries. "
        "The C++ client won't link successfully without it."
    )

    # Build both demanded artifacts rather than trusting pre-created files.
    run_checked(["cargo", "build"], rust_dir)
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(build_dir)
    run_checked(["cmake", ".."], build_dir)
    run_checked(["cmake", "--build", ".", "--", "-j2"], build_dir)
    assert os.path.isfile(exe_path), "CMake did not produce build/feature_test"
    assert os.access(exe_path, os.X_OK), "The rebuilt feature_test is not executable"

    # A real integration client must not fabricate a successful response while
    # no service is listening.
    kill_port_listeners(50051)
    offline_id = "offline-" + secrets.token_hex(8)
    offline = subprocess.run(
        [exe_path, offline_id], cwd=build_dir, capture_output=True, text=True, timeout=10
    )
    assert offline.returncode != 0, (
        "feature_test reported success while no server was listening; it does not "
        "demonstrate a real gRPC integration"
    )

    server_path = os.path.join(rust_dir, "target", "debug", "backend_rust")
    assert os.path.isfile(server_path) and os.access(server_path, os.X_OK), (
        "cargo build did not produce an executable Rust server"
    )

    server = None
    try:
        server = subprocess.Popen(
            [server_path],
            cwd=rust_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        wait_for_server(server)

        # Exercise answers derived by the verifier on unpredictable IDs.
        ids = ["verify-" + secrets.token_hex(10) for _ in range(3)]
        ids.append("778899")
        fixed_stdout = None
        for request_id in ids:
            result = subprocess.run(
                [exe_path, request_id],
                cwd=build_dir,
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"C++ client failed for ID {request_id}:\n{result.stderr}"
            )
            expected = f"FeatureData-{request_id}\n"
            assert result.stdout == expected, (
                f"Unexpected client stdout for ID {request_id}: "
                f"expected {expected!r}, got {result.stdout!r}"
            )
            assert server.poll() is None, "Rust server exited during integration testing"
            if request_id == "778899":
                fixed_stdout = result.stdout

        # The submitted log must be the exact stdout produced for the required ID.
        assert original_log == fixed_stdout, (
            f"{log_path} is not the exact stdout of feature_test 778899: "
            f"expected {fixed_stdout!r}, got {original_log!r}"
        )
    finally:
        if server is not None and server.poll() is None:
            try:
                os.killpg(server.pid, signal.SIGTERM)
                server.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(server.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
