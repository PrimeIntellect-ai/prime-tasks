#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import time
from pathlib import Path

import pytest

APP_DIR = "/home/user/app"
SO_FILE = os.path.join(APP_DIR, "libbackend.so")
SERVER_FILE = os.path.join(APP_DIR, "server.py")
VALGRIND_LOG = os.path.join(APP_DIR, "valgrind_fixed.log")


def test_libbackend_compiled_and_functional(tmp_path):
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} was not found. Did you compile it?"
    assert Path(SO_FILE).read_bytes()[:4] == b"\x7fELF", f"{SO_FILE} is not an ELF shared library."

    source = tmp_path / "check_backend.cpp"
    binary = tmp_path / "check_backend"
    vg_log = tmp_path / "backend_valgrind.log"
    source.write_text(r'''
#include <dlfcn.h>
#include <cstring>
#include <iostream>
#include <string>

using process_fn = char* (*)(const char*);

int main(int argc, char** argv) {
    if (argc != 6) return 20;
    void* handle = dlopen("/home/user/app/libbackend.so", RTLD_NOW);
    if (!handle) {
        std::cerr << dlerror() << std::endl;
        return 21;
    }
    dlerror();
    process_fn process_data = reinterpret_cast<process_fn>(dlsym(handle, "process_data"));
    const char* error = dlerror();
    if (error || !process_data) return 22;

    for (int i = 1; i < argc; ++i) {
        char* result = process_data(argv[i]);
        std::string expected = std::string("Processed: ") + argv[i];
        if (!result || expected != result) {
            std::cerr << "Unexpected result for input " << argv[i] << std::endl;
            return 23;
        }
    }
    dlclose(handle);
    return 0;
}
''')
    subprocess.run(
        ["g++", "-O0", "-o", str(binary), str(source), "-ldl"],
        check=True,
        capture_output=True,
        text=True,
    )

    tokens = [f"probe-{os.urandom(8).hex()}-{i}" for i in range(5)]
    with open(vg_log, "w") as log:
        result = subprocess.run(
            [
                "valgrind", "--leak-check=full", "--show-leak-kinds=definite",
                "--errors-for-leak-kinds=definite", "--error-exitcode=99",
                str(binary), *tokens,
            ],
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
            timeout=30,
        )
    assert result.returncode == 0, f"The shared library failed functional or Valgrind checks; see {vg_log}."
    content = vg_log.read_text(errors="replace")
    assert re.search(r"definitely lost:\s+0 bytes", content), "Valgrind found a definite leak in process_data."


def _socat_pids_with_expected_command():
    result = subprocess.run(["ps", "aux"], capture_output=True, text=True, check=True)
    lines = [line for line in result.stdout.splitlines() if "socat" in line and "grep" not in line]
    assert lines, "No socat process is running."
    valid_lines = [line for line in lines if "8000" in line and "9000" in line]
    assert valid_lines, "socat is running, but doesn't seem to be configured to proxy port 8000 to 9000."

    pids = []
    for line in valid_lines:
        fields = line.split()
        if len(fields) > 1 and fields[1].isdigit():
            pids.append(int(fields[1]))
    return pids


def _listening_inodes(port):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    return inodes


def test_socat_running_and_owns_listener():
    pids = _socat_pids_with_expected_command()
    listener_inodes = _listening_inodes(8000)
    assert listener_inodes, "Nothing is listening on TCP port 8000."

    owned = False
    for pid in pids:
        fd_dir = Path(f"/proc/{pid}/fd")
        try:
            links = [os.readlink(path) for path in fd_dir.iterdir()]
        except (OSError, FileNotFoundError, PermissionError):
            continue
        if any(link.startswith("socket:[") and link[8:-1] in listener_inodes for link in links):
            owned = True
            break
    assert owned, "The required socat process does not own the listener on TCP port 8000."


def test_original_valgrind_report_and_exact_request_count():
    assert os.path.isfile(VALGRIND_LOG), f"Valgrind log {VALGRIND_LOG} was not found."
    content = Path(VALGRIND_LOG).read_text(errors="replace")
    assert "Memcheck" in content and "HEAP SUMMARY:" in content and "LEAK SUMMARY:" in content, (
        "valgrind_fixed.log does not contain a complete Valgrind report."
    )
    assert "definitely lost: 0 bytes" in content, (
        "Memory leak is still present. 'definitely lost: 0 bytes' not found in valgrind log."
    )
    request_count = len(re.findall(r'"GET / HTTP/1\.[01]"\s+200\b', content))
    assert request_count == 5, f"Expected exactly 5 successful GET requests in the profiling log, found {request_count}."


def test_service_through_proxy_under_valgrind(tmp_path):
    live_log = tmp_path / "live_valgrind.log"
    with open(live_log, "w") as log:
        proc = subprocess.Popen(
            ["valgrind", "--leak-check=full", "python3", SERVER_FILE],
            stdout=log,
            stderr=log,
        )
        try:
            deadline = time.time() + 10
            while time.time() < deadline:
                if proc.poll() is not None:
                    pytest.fail(f"The Python service exited before accepting requests; see {live_log}.")
                try:
                    with socket.create_connection(("127.0.0.1", 9000), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                pytest.fail("The Python service did not start on port 9000.")

            # Exercise the actual port-8000 route with exactly five HTTP GET requests.
            for _ in range(5):
                response = subprocess.run(
                    ["curl", "--fail", "--silent", "--show-error", "http://127.0.0.1:8000/"],
                    capture_output=True,
                    timeout=10,
                )
                assert response.returncode == 0, response.stderr.decode(errors="replace")
                assert response.stdout == b"Processed: Test Data", "The proxied service returned an incorrect response."
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)

    content = live_log.read_text(errors="replace")
    assert "Memcheck" in content and "HEAP SUMMARY:" in content, "The verifier's Valgrind run did not complete."
    assert re.search(r"definitely lost:\s+0 bytes", content), "The running service has definitely lost memory."
    assert len(re.findall(r'"GET / HTTP/1\.[01]"\s+200\b', content)) == 5, (
        "The live service did not handle exactly five successful GET requests."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
