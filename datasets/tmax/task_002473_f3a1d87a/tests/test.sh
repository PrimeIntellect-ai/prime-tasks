#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'FLOCK_EOF' > /tmp/flock_probe.c
#define _GNU_SOURCE
#include <sys/file.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = NULL;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    if (!real_flock) return -1;

    int rc = real_flock(fd, operation);
    int saved_errno = errno;
    const char *marker = getenv("FLOCK_PROBE_FILE");
    if (rc == 0 && marker && ((operation & LOCK_EX) || (operation & LOCK_UN))) {
        int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            char buf[80];
            char kind = (operation & LOCK_UN) ? 'U' : 'E';
            int n = snprintf(buf, sizeof(buf), "%ld %c\n", (long)getpid(), kind);
            if (n > 0) write(out, buf, (size_t)n);
            close(out);
        }
    }
    errno = saved_errno;
    return rc;
}
FLOCK_EOF
gcc -shared -fPIC -o /tmp/flock_probe.so /tmp/flock_probe.c -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

import pytest

SCANNER_PATH = "/home/user/scanner"
SOURCE_PATH = "/home/user/scanner.cpp"
LOG_PATH = "/home/user/artifact_log.txt"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
SIGNATURE = b"EVIL_CORP_BACKDOOR_2024"
FLOCK_PROBE = "/tmp/flock_probe.so"
FLOCK_MARKER = "/tmp/flock_calls.txt"


def test_scanner_exists():
    assert os.path.isfile(SCANNER_PATH), f"Scanner binary not found at {SCANNER_PATH}"
    assert os.access(SCANNER_PATH, os.X_OK), f"Scanner at {SCANNER_PATH} is not executable"
    with open(SCANNER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Scanner must be a compiled executable, not a script"


def test_cpp_source_uses_required_interfaces():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]zlib\.h[>\"]", source), "scanner.cpp must use zlib"
    assert (re.search(r"\bgzopen\s*\(", source) and re.search(r"\bgzread\s*\(", source)) or re.search(r"\binflate(?:Init2|Init|)\s*\(", source), "scanner.cpp must decompress through zlib"
    assert re.search(r"#\s*include\s*[<\"]sys/file\.h[>\"]", source), "scanner.cpp must include the POSIX flock interface"
    assert re.search(r"\bflock\s*\(", source), "scanner.cpp must call flock"
    assert not re.search(r"\b(?:system|popen)\s*\(", source), "External shell commands may not be used for decompression"


def test_adversarial_corpus_and_logging():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing at {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing at {EVIL_CORPUS}"

    clean_files = sorted([os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if f.endswith('.gz')])
    evil_files = sorted([os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if f.endswith('.gz')])

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    clean_failed = []
    evil_failed = []

    def run_scanner(filepath):
        result = subprocess.run([SCANNER_PATH, filepath], capture_output=True)
        return filepath, result.returncode

    with ThreadPoolExecutor(max_workers=20) as executor:
        clean_results = list(executor.map(run_scanner, clean_files))
        evil_results = list(executor.map(run_scanner, evil_files))

    for filepath, code in clean_results:
        if code != 0:
            clean_failed.append(os.path.basename(filepath))

    for filepath, code in evil_results:
        if code != 1:
            evil_failed.append(os.path.basename(filepath))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    assert os.path.isfile(LOG_PATH), f"Log file not found at {LOG_PATH}"
    with open(LOG_PATH, 'r') as f:
        lines = f.read().splitlines()

    expected_entries = set()
    for filepath in clean_files:
        expected_entries.add(f"{os.path.basename(filepath)} - CLEAN")
    for filepath in evil_files:
        expected_entries.add(f"{os.path.basename(filepath)} - REJECTED")

    actual_entries = set(lines)
    missing_entries = expected_entries - actual_entries
    assert not missing_entries, f"Missing expected log entries: {missing_entries}"
    for line in lines:
        assert line in expected_entries, f"Unexpected or corrupted log entry found: '{line}'"


def _clean_bytes(size):
    data = os.urandom(size)
    while SIGNATURE in data:
        data = os.urandom(size)
    return data


def test_generated_hidden_inputs_parallel_logging_and_runtime_flock():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="scanner-evaluation-") as root:
        paths_and_expected = []
        offsets = [0, 1, 4095, 4096, 8191, 8192, 16383, 32767]

        for i in range(48):
            malicious = (i % 2 == 0)
            size = rng.randint(50000, 220000)
            data = bytearray(_clean_bytes(size))
            if malicious:
                offset = offsets[i // 2 % len(offsets)] if i < 16 else rng.randint(0, size - len(SIGNATURE))
                data[offset:offset + len(SIGNATURE)] = SIGNATURE
            else:
                # Similar-looking text must not count as the exact signature.
                decoy = b"EVIL_CORP_BACKDOOR_202X"
                offset = rng.randint(0, size - len(decoy))
                data[offset:offset + len(decoy)] = decoy

            dirname = os.path.join(root, secrets.token_hex(8))
            os.mkdir(dirname)
            basename = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(20)) + ".gz"
            path = os.path.join(dirname, basename)
            with gzip.open(path, "wb", compresslevel=rng.randint(1, 9)) as out:
                out.write(data)
            paths_and_expected.append((path, 1 if malicious else 0))

        rng.shuffle(paths_and_expected)
        for path in (LOG_PATH, FLOCK_MARKER):
            if os.path.exists(path):
                os.remove(path)

        env = os.environ.copy()
        env["LD_PRELOAD"] = FLOCK_PROBE
        env["FLOCK_PROBE_FILE"] = FLOCK_MARKER

        def run_case(item):
            path, expected = item
            proc = subprocess.run([SCANNER_PATH, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=env, timeout=15)
            return path, expected, proc.returncode

        with ThreadPoolExecutor(max_workers=24) as executor:
            results = list(executor.map(run_case, paths_and_expected))

        failures = [(os.path.basename(p), expected, actual) for p, expected, actual in results if actual != expected]
        assert not failures, f"Generated artifact classifications failed: {failures}"

        assert os.path.isfile(LOG_PATH), "Scanner did not create the required log"
        with open(LOG_PATH, "r", errors="strict") as f:
            actual_lines = f.read().splitlines()
        expected_lines = [f"{os.path.basename(path)} - {'REJECTED' if code == 1 else 'CLEAN'}"
                          for path, code in paths_and_expected]
        assert collections.Counter(actual_lines) == collections.Counter(expected_lines), "Concurrent log is missing, duplicated, or corrupted"
        assert len(actual_lines) == len(expected_lines), "Scanner must append exactly one complete line per invocation"

        assert os.path.isfile(FLOCK_MARKER), "No runtime calls to flock were observed"
        calls = collections.defaultdict(list)
        with open(FLOCK_MARKER, "r") as f:
            for line in f:
                pid, kind = line.split()
                calls[pid].append(kind)
        assert len(calls) == len(paths_and_expected), "Every scanner invocation must use flock"
        for pid, kinds in calls.items():
            assert "E" in kinds, f"Scanner process {pid} did not acquire an exclusive flock"
            assert "U" in kinds, f"Scanner process {pid} did not release its flock"


def test_exactly_one_argument_required():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    no_arg = subprocess.run([SCANNER_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    two_args = subprocess.run([SCANNER_PATH, "/tmp/a.gz", "/tmp/b.gz"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert no_arg.returncode != 0, "Invocation with no artifact argument must fail"
    assert two_args.returncode != 0, "Invocation with more than one artifact argument must fail"
    assert not os.path.exists(LOG_PATH) or os.path.getsize(LOG_PATH) == 0, "Invalid invocations must not log an artifact result"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
