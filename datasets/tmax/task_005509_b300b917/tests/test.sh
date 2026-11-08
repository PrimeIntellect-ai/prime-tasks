#!/bin/bash
mkdir -p /logs/verifier

cat << 'WATCH_EOF' > /tmp/watch_extract_exec.c
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

__attribute__((constructor)) static void watch_extract_record(void) {
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0) return;
    exe[n] = '\0';

    const char *base = strrchr(exe, '/');
    base = base ? base + 1 : exe;
    if (strcmp(base, "extract_record") != 0) return;

    const char *marker = getenv("EXEC_WATCH_MARKER");
    if (!marker || !*marker) return;

    int fd = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        const char msg[] = "executed\n";
        write(fd, msg, sizeof(msg) - 1);
        close(fd);
    }
}
WATCH_EOF

gcc -shared -fPIC -o /tmp/watch_extract_exec.so /tmp/watch_extract_exec.c 2>/dev/null

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT = "/home/user/analyze_leak.sh"
SOURCE = "/home/user/extract_record.c"
EXECUTABLE = "/home/user/extract_record"
DUMP = "/home/user/memory.dump"
OUTPUT = "/home/user/leak_root_cause.txt"
WATCHER = "/tmp/watch_extract_exec.so"


def write_dump(encoded):
    data = os.urandom(0x3A) + encoded + os.urandom(20)
    with open(DUMP, "wb") as f:
        f.write(data)
    return data


def run_workflow_from_scratch(encoded, expected_plaintext):
    original_dump = write_dump(encoded)

    for path in (EXECUTABLE, OUTPUT):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    fd, marker = tempfile.mkstemp(prefix="extract_record_exec_", dir="/tmp")
    os.close(fd)
    os.unlink(marker)

    env = os.environ.copy()
    env["LD_PRELOAD"] = WATCHER
    env["EXEC_WATCH_MARKER"] = marker

    result = subprocess.run(
        ["bash", SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "FAIL: analyze_leak.sh did not complete successfully.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )

    assert os.path.isfile(marker), (
        "FAIL: analyze_leak.sh did not execute /home/user/extract_record."
    )
    os.unlink(marker)

    assert os.path.isfile(EXECUTABLE), "FAIL: analyze_leak.sh did not create extract_record."
    assert os.access(EXECUTABLE, os.X_OK), "FAIL: extract_record is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "FAIL: extract_record is not a compiled ELF executable."

    extracted = subprocess.run(
        [EXECUTABLE, DUMP],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert extracted.returncode == 0, (
        "FAIL: extract_record failed when run against memory.dump.\n"
        f"stderr: {extracted.stderr.decode(errors='replace')}"
    )
    assert extracted.stdout.strip() == encoded, (
        "FAIL: extract_record did not extract the complete encoded payload from the dump."
    )

    with open(DUMP, "rb") as f:
        assert f.read() == original_dump, "FAIL: the workflow modified memory.dump."

    assert os.path.isfile(OUTPUT), "FAIL: analyze_leak.sh did not generate leak_root_cause.txt."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == expected_plaintext, (
        f"FAIL: decoded output was incorrect. Expected '{expected_plaintext}', got '{content}'."
    )


def test_00_reproducible_workflow_on_supplied_payload():
    expected = "CRITICAL_LEAK_IN_SESSION_MANAGER_0x88A1"
    encoded = base64.b64encode(expected.encode("ascii"))
    run_workflow_from_scratch(encoded, expected)


def test_analyze_leak_script_exists():
    path = "/home/user/analyze_leak.sh"
    assert os.path.isfile(path), f"FAIL: Expected bash script {path} is missing."


def test_extract_record_executable_exists():
    path = "/home/user/extract_record"
    assert os.path.isfile(path), f"FAIL: Expected executable {path} is missing. The C program was not compiled."
    assert os.access(path, os.X_OK), f"FAIL: {path} is not executable."


def test_leak_root_cause_file_exists_and_content():
    path = "/home/user/leak_root_cause.txt"
    assert os.path.isfile(path), f"FAIL: Expected output file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "CRITICAL_LEAK_IN_SESSION_MANAGER_0x88A1"
    assert content == expected, f"FAIL: Incorrect content in {path}. Expected '{expected}', got '{content}'."


def test_workflow_handles_an_unseen_payload():
    expected = "RANDOM_LEAK__" + secrets.token_hex(13)
    assert len(expected) == 39
    encoded = base64.b64encode(expected.encode("ascii"))
    assert len(encoded) == 52
    run_workflow_from_scratch(encoded, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
