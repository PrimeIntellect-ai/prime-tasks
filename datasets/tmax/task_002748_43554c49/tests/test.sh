#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import subprocess

PROJECT = "/home/user/telemetryd"
LOG_DIR = "/home/user/logs"


def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_log = "Faulty Log: log_073.bin"
    expected_bytes = "Leaked Bytes per request: 25"

    assert expected_log in content, f"Report does not correctly identify the faulty log. Expected '{expected_log}'."
    assert expected_bytes in content, f"Report does not correctly identify the leaked bytes. Expected '{expected_bytes}'."

    # Independently derive the unique malformed record and allocation size from
    # the supplied binary logs, then enforce the requested exact report format.
    malformed = []
    for name in sorted(n for n in os.listdir(LOG_DIR) if re.fullmatch(r"log_\d{3}\.bin", n)):
        with open(os.path.join(LOG_DIR, name), "rb") as f:
            data = f.read()
        assert len(data) >= 2, f"{name} is missing its length header"
        total_len = struct.unpack("!H", data[:2])[0]
        payload = data[2:]
        assert len(payload) == total_len, f"{name} has inconsistent framing"

        offset = 0
        while offset < total_len:
            item_len = payload[offset]
            if item_len == 0:
                offset += 1
                continue
            if offset + 1 + item_len > total_len:
                malformed.append((name, item_len))
                break
            offset += 1 + item_len

    assert len(malformed) == 1, f"Expected one malformed log, found {malformed}"
    derived_name, derived_bytes = malformed[0]
    expected = f"Faulty Log: {derived_name}\nLeaked Bytes per request: {derived_bytes}"
    assert content == expected, f"Report must have the exact requested format and derived values:\n{expected}"


def test_parser_h_fixed():
    parser_path = os.path.join(PROJECT, "parser.h")
    assert os.path.isfile(parser_path), f"{parser_path} is missing."

    with open(parser_path, "r") as f:
        content = f.read()

    assert "<stdint.h>" in content, "parser.h is still missing the #include <stdint.h> directive."


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-pthread" in content, "Makefile is still missing the -pthread flag required for compilation."


def test_telemetryd_compiles():
    subprocess.run(["make", "clean"], cwd=PROJECT, capture_output=True)
    result = subprocess.run(["make"], cwd=PROJECT, capture_output=True, text=True)
    assert result.returncode == 0, f"Compilation failed after fixes:\n{result.stdout}\n{result.stderr}"

    exe_path = os.path.join(PROJECT, "telemetryd")
    assert os.path.isfile(exe_path), f"Executable {exe_path} was not created by make."
    assert os.access(exe_path, os.X_OK), f"Executable {exe_path} is not executable."


def test_server_c_memory_leak_fixed():
    server_path = os.path.join(PROJECT, "server.c")
    assert os.path.isfile(server_path), f"{server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    # Preserve the original structural assertion.
    bounds_check_pattern = re.compile(r"if\s*\([^)]*>\s*total_len\s*\)\s*\{([^}]*)\}")
    match = bounds_check_pattern.search(content)
    assert match is not None, "Could not find the bounds check logic in server.c"

    block_content = match.group(1)
    assert "free" in block_content and "item" in block_content, \
        "The memory leak is not fixed. Missing free(item) in the out-of-bounds error handling block."

    # Execute the submitted request handler on every supplied log under
    # Valgrind. This makes comments or dead-code mentions of free(item)
    # insufficient: the malformed request must actually release its allocation.
    harness_source = r'''
#define main telemetryd_daemon_main
#include "/home/user/telemetryd/server.c"
#undef main

#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>

static int replay(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 10;

    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < 0) {
        close(fd);
        return 11;
    }

    size_t size = (size_t)st.st_size;
    char *data = malloc(size ? size : 1);
    if (!data) {
        close(fd);
        return 12;
    }

    size_t got = 0;
    while (got < size) {
        ssize_t n = read(fd, data + got, size - got);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            free(data);
            close(fd);
            return 13;
        }
        got += (size_t)n;
    }
    close(fd);

    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) {
        free(data);
        return 14;
    }

    size_t sent = 0;
    while (sent < size) {
        ssize_t n = write(sv[1], data + sent, size - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            free(data);
            close(sv[0]);
            close(sv[1]);
            return 15;
        }
        sent += (size_t)n;
    }
    free(data);
    shutdown(sv[1], SHUT_WR);

    int *client_sock = malloc(sizeof(*client_sock));
    if (!client_sock) {
        close(sv[0]);
        close(sv[1]);
        return 16;
    }
    *client_sock = sv[0];
    handle_client(client_sock);
    close(sv[1]);
    return 0;
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; ++i) {
        int rc = replay(argv[i]);
        if (rc != 0) return rc;
    }
    return 0;
}
'''
    harness_c = "/tmp/telemetry_valgrind_harness.c"
    harness_bin = "/tmp/telemetry_valgrind_harness"
    with open(harness_c, "w") as f:
        f.write(harness_source)

    compile_result = subprocess.run(
        ["gcc", "-g", "-Wall", "-pthread", "-o", harness_bin, harness_c],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, (
        "Could not build the runtime leak-test harness against submitted server.c:\n"
        + compile_result.stdout + compile_result.stderr
    )

    logs = [os.path.join(LOG_DIR, f"log_{i:03d}.bin") for i in range(100)]
    assert all(os.path.isfile(path) for path in logs), "One or more required log files are missing"

    result = subprocess.run(
        [
            "/usr/bin/valgrind",
            "--leak-check=full",
            "--show-leak-kinds=all",
            "--errors-for-leak-kinds=definite,indirect,possible",
            "--error-exitcode=99",
            harness_bin,
            *logs,
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "The submitted service did not process all 100 logs cleanly under Valgrind "
        f"(exit {result.returncode}):\n{result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
