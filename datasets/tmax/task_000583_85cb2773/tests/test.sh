#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import textwrap
import time

BUILD_DIR = "/home/user/api_server"
EXPECTED = ["200", "200", "429"]


def strip_c_comments(source):
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    return re.sub(r'//[^\n]*', '', source)


def test_compilation_and_executable():
    subprocess.run(["make", "clean"], cwd=BUILD_DIR, capture_output=True)
    result = subprocess.run(["make"], cwd=BUILD_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"

    server = os.path.join(BUILD_DIR, "server")
    assert os.path.isfile(server), "Executable 'server' was not created."
    assert os.access(server, os.X_OK), "The produced server is not executable."


def test_requested_source_fixes_are_present():
    api_path = os.path.join(BUILD_DIR, "api.c")
    hash_path = os.path.join(BUILD_DIR, "hash.c")
    main_path = os.path.join(BUILD_DIR, "main.c")
    for path in (api_path, hash_path, main_path):
        assert os.path.isfile(path), f"{path} does not exist."

    api = strip_c_comments(open(api_path).read())
    error_path = None
    for match in re.finditer(r'\bif\s*\(', api):
        candidate = api[match.start():match.start() + 1500]
        end = re.search(r'\breturn\s+400\s*;', candidate)
        if end and "auth_header" in candidate[:end.end()]:
            error_path = candidate[:end.end()]
            break
    assert error_path is not None, "Could not find the invalid-authorization path returning 400."
    assert re.search(r'\bfree\s*\(\s*ctx\s*->\s*ip_addr\s*\)\s*;', error_path), \
        "The invalid request path does not free ctx->ip_addr."
    assert re.search(r'\bfree\s*\(\s*ctx\s*\)\s*;', error_path), \
        "The invalid request path does not free ctx."

    hash_source = strip_c_comments(open(hash_path).read())
    asm_match = re.search(r'__asm__\s*(?:volatile\s*)?\((.*?)\)\s*;', hash_source, re.S)
    assert asm_match is not None, "Could not find the inline assembly in hash.c."
    parts = asm_match.group(1).split(':')
    assert len(parts) >= 4, "The inline assembly has no clobber section."
    assert re.search(r'(?<![A-Za-z0-9_])%?(?:e|r)ax(?![A-Za-z0-9_])', parts[-1]), \
        "The inline assembly clobber list does not contain eax/rax."

    main_source = strip_c_comments(open(main_path).read())
    assert re.search(r'\bsocklen_t\s+addrlen\s*=\s*sizeof\s*\(\s*address\s*\)\s*;', main_source), \
        "addrlen must have the socket API's socklen_t type."
    assert not re.search(r'\(\s*socklen_t\s*\*\s*\)\s*&\s*addrlen', main_source), \
        "The accept call still type-puns addrlen through a socklen_t pointer cast."


def test_hash_rate_limit_and_invalid_path_under_sanitizers():
    harness = "/tmp/api_harness.c"
    with open(harness, "w") as f:
        f.write(textwrap.dedent(r'''
            #include <stdint.h>
            #include <stdio.h>
            #include <string.h>
            #include "api.h"

            extern uint32_t fast_hash(const char *s);

            static uint32_t portable_hash(const char *s) {
                uint32_t h = 5381u;
                while (*s) h = h * 33u + (unsigned char)*s++;
                return h;
            }

            int main(void) {
                char value[128];
                const char *fixed[] = {
                    "", "127.0.0.1", "10.20.30.40", "abcdefghijklmnopqrstuvwxyz",
                    "same-ip-for-rate-limit", "Bearer token123"
                };
                for (unsigned i = 0; i < sizeof(fixed) / sizeof(fixed[0]); ++i) {
                    if (fast_hash(fixed[i]) != portable_hash(fixed[i])) return 10;
                }
                for (unsigned i = 0; i < 2000; ++i) {
                    snprintf(value, sizeof(value), "generated-%u-%08x-%08x", i,
                             i * 2654435761u, (i + 17u) * 2246822519u);
                    if (fast_hash(value) != portable_hash(value)) return 11;
                }

                for (int i = 0; i < 64; ++i) {
                    if (process_request("198.51.100.20", NULL) != 400) return 20;
                    if (process_request("198.51.100.21", "invalid") != 400) return 21;
                }

                if (process_request("203.0.113.77", "Bearer token123") != 200) return 30;
                if (process_request("203.0.113.77", "Bearer token123") != 200) return 31;
                if (process_request("203.0.113.77", "Bearer token123") != 429) return 32;
                return 0;
            }
        '''))

    binary = "/tmp/api_harness"
    compile_result = subprocess.run([
        "gcc", "-std=gnu11", "-Wall", "-Werror", "-O3",
        "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
        "-I", BUILD_DIR,
        os.path.join(BUILD_DIR, "api.c"),
        os.path.join(BUILD_DIR, "hash.c"),
        harness, "-o", binary
    ], capture_output=True, text=True)
    assert compile_result.returncode == 0, \
        f"Sanitized harness failed to compile:\n{compile_result.stdout}\n{compile_result.stderr}"

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=99"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    result = subprocess.run([binary], capture_output=True, text=True, env=env, timeout=20)
    assert result.returncode == 0, \
        f"Functional or sanitizer test failed (exit {result.returncode}):\n{result.stdout}\n{result.stderr}"


def send_request(headers=""):
    request = (
        "POST /api/submit HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        f"{headers}"
        "Content-Length: 0\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
        sock.sendall(request)
        data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
    first_line = data.split(b"\r\n", 1)[0].decode("ascii", "replace")
    match = re.match(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b', first_line)
    assert match, f"Invalid HTTP response: {data!r}"
    return int(match.group(1))


def test_real_server_and_results_log():
    try:
        subprocess.run(["pkill", "-x", "server"], capture_output=True)
    except FileNotFoundError:
        pass
    time.sleep(0.2)

    server_path = os.path.join(BUILD_DIR, "server")
    proc = subprocess.Popen([server_path], cwd=BUILD_DIR,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    try:
        deadline = time.time() + 5
        malformed_status = None
        while time.time() < deadline:
            assert proc.poll() is None, "The server exited before accepting requests."
            try:
                malformed_status = send_request()
                break
            except (ConnectionRefusedError, socket.timeout, OSError):
                time.sleep(0.05)
        assert malformed_status == 400, \
            f"A request without Authorization should return 400, got {malformed_status}."

        actual = [send_request("Authorization: Bearer token123\r\n") for _ in range(3)]
        assert actual == EXPECTED, f"Live server returned {actual}, expected {EXPECTED}."
        assert proc.poll() is None, "The server crashed while processing requests."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)

    log_path = os.path.join(BUILD_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path) as f:
        logged = [line.strip() for line in f if line.strip()]
    assert logged == [str(x) for x in EXPECTED], \
        f"Expected 200, 200, 429 in test_results.log, got {logged}."
    assert logged == [str(x) for x in actual], \
        "test_results.log does not match the statuses recomputed from the live server."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
