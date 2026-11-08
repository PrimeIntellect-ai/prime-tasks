#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/stream_filter"
SOURCE = "/home/user/stream_filter.c"
EVIL_DIR = "/app/corpus/evil/"
CLEAN_DIR = "/app/corpus/clean/"
CONFIG = "/app/backup.conf"
SIGNATURE = b"MALWARE_SIG_2024"


def run_filter(executable, data, env=None):
    return subprocess.run(
        [executable], input=data, capture_output=True, env=env, timeout=5
    )


@pytest.fixture(scope="session")
def rebuilt_executable():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} not found."
    build_dir = tempfile.mkdtemp(prefix="stream_filter_build_")
    output = os.path.join(build_dir, "stream_filter")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", output],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"
    return output


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile your C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "stream_filter must be a compiled executable."


def test_adversarial_corpus():
    """Test the stream filter against the supplied evil and clean corpora."""
    assert os.path.isdir(EVIL_DIR), f"Evil directory {EVIL_DIR} missing."
    assert os.path.isdir(CLEAN_DIR), f"Clean directory {CLEAN_DIR} missing."

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    bypassed_evil = []
    modified_clean = []

    for ef in evil_files:
        with open(ef, "rb") as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True, timeout=5)
            if result.returncode != 1:
                bypassed_evil.append(os.path.basename(ef))

    for cf in clean_files:
        with open(cf, "rb") as f:
            original_data = f.read()
            f.seek(0)
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True, timeout=5)
            if result.returncode != 0 or result.stdout != original_data:
                modified_clean.append(os.path.basename(cf))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def clean_random(length):
    data = bytearray(secrets.token_bytes(length))
    while SIGNATURE in data:
        at = data.find(SIGNATURE)
        data[at + len(SIGNATURE) // 2] ^= 1
    return bytes(data)


def generated_cases():
    clean = [
        b"",
        b"A",
        SIGNATURE[:-1],
        b"prefix-" + SIGNATURE[:-1] + b"-suffix",
        SIGNATURE[:8] + b"X" + SIGNATURE[9:],
        bytes(range(256)),
    ]
    for length in (11, 12, 13, 23, 24, 25, 31, 47, 128, 1024, 4097):
        clean.append(clean_random(length))

    evil = []
    # These offsets include both sides of every boundary around the configured
    # 12-byte read size, including signatures split across consecutive reads.
    for offset in (0, 1, 5, 11, 12, 13, 23, 24, 25, 35, 36, 47, 71):
        prefix = clean_random(offset)
        suffix = clean_random(secrets.randbelow(80) + 1)
        evil.append(prefix + SIGNATURE + suffix)
    evil.append(clean_random(19) + SIGNATURE + clean_random(7) + SIGNATURE + clean_random(33))
    return clean, evil


@pytest.mark.parametrize("which", ["submitted", "rebuilt"])
def test_generated_hidden_inputs(which, rebuilt_executable):
    executable = EXECUTABLE if which == "submitted" else rebuilt_executable
    clean, evil = generated_cases()

    # Include clean inputs having the same lengths as malicious inputs, so
    # classifications based only on known sizes cannot pass.
    clean.extend(clean_random(len(data)) for data in evil)

    for index, data in enumerate(clean):
        result = run_filter(executable, data)
        assert result.returncode == 0, f"generated clean case {index} was rejected"
        assert result.stdout == data, f"generated clean case {index} was modified"

    for index, data in enumerate(evil):
        result = run_filter(executable, data)
        assert result.returncode == 1, f"generated malicious case {index} was not rejected"


def test_configured_read_size(rebuilt_executable, tmp_path):
    with open(CONFIG, "r", encoding="utf-8") as f:
        match = re.search(r"^\s*BUFFER_SIZE\s*=\s*(\d+)\s*$", f.read(), re.MULTILINE)
    assert match, "BUFFER_SIZE is missing from backup.conf"
    buffer_size = int(match.group(1))

    hook_source = tmp_path / "read_hook.c"
    hook_library = tmp_path / "read_hook.so"
    trace_file = tmp_path / "read_trace.txt"
    hook_source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

static void record_request(char kind, size_t count) {
    const char *path = getenv("STREAM_FILTER_READ_TRACE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    char line[80];
    int n = snprintf(line, sizeof(line), "%c %zu\n", kind, count);
    if (n > 0) write(fd, line, (size_t)n);
    close(fd);
}

ssize_t read(int fd, void *buf, size_t count) {
    static ssize_t (*real_read)(int, void *, size_t) = NULL;
    if (!real_read) real_read = dlsym(RTLD_NEXT, "read");
    if (fd == STDIN_FILENO) record_request('R', count);
    return real_read(fd, buf, count);
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real_fread)(void *, size_t, size_t, FILE *) = NULL;
    if (!real_fread) real_fread = dlsym(RTLD_NEXT, "fread");
    if (fileno(stream) == STDIN_FILENO) record_request('F', size * nmemb);
    return real_fread(ptr, size, nmemb, stream);
}

size_t fread_unlocked(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real_fread_unlocked)(void *, size_t, size_t, FILE *) = NULL;
    if (!real_fread_unlocked) real_fread_unlocked = dlsym(RTLD_NEXT, "fread_unlocked");
    if (fileno(stream) == STDIN_FILENO) record_request('F', size * nmemb);
    return real_fread_unlocked(ptr, size, nmemb, stream);
}
''', encoding="utf-8")

    built = subprocess.run(
        ["gcc", "-shared", "-fPIC", str(hook_source), "-o", str(hook_library), "-ldl"],
        capture_output=True,
        text=True,
    )
    assert built.returncode == 0, built.stderr

    env = os.environ.copy()
    env["LD_PRELOAD"] = str(hook_library)
    env["STREAM_FILTER_READ_TRACE"] = str(trace_file)
    data = clean_random(buffer_size * 4 + 5)
    result = run_filter(rebuilt_executable, data, env=env)
    assert result.returncode == 0 and result.stdout == data
    assert trace_file.exists(), "No stdin read operation was observed"

    entries = []
    for line in trace_file.read_text(encoding="ascii").splitlines():
        kind, count = line.split()
        entries.append((kind, int(count)))
    fread_requests = [count for kind, count in entries if kind == "F"]
    read_requests = [count for kind, count in entries if kind == "R"]
    requests = fread_requests if fread_requests else read_requests
    assert requests, "No supported C stdin read operation was observed"
    assert all(count == buffer_size for count in requests), (
        f"stdin must be requested in exactly {buffer_size}-byte chunks; observed {requests}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
