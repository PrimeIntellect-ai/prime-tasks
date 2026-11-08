#!/bin/bash
mkdir -p /logs/verifier

cat << 'WRAP_EOF' > /tmp/locktrace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

static int is_target_fd(int fd) {
    const char *target = getenv("DATASET_TRACE_OUTPUT");
    if (!target || !*target) return 0;
    char linkpath[64], actual[PATH_MAX];
    snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(linkpath, actual, sizeof(actual) - 1);
    if (n < 0) return 0;
    actual[n] = '\0';
    return strcmp(actual, target) == 0;
}

static void record_event(char kind, int fd) {
    if (!is_target_fd(fd)) return;
    const char *logpath = getenv("DATASET_LOCK_TRACE");
    if (!logpath || !*logpath) return;
    int out = (int)syscall(SYS_openat, AT_FDCWD, logpath,
                           O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (out < 0) return;
    char buf[80];
    int n = snprintf(buf, sizeof(buf), "%c %ld\n", kind,
                     (long)syscall(SYS_gettid));
    syscall(SYS_write, out, buf, (size_t)n);
    syscall(SYS_close, out);
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int);
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    int rc = real_flock(fd, operation);
    if (rc == 0) record_event((operation & LOCK_UN) ? 'U' : 'L', fd);
    return rc;
}

static int fcntl_has_no_arg(int cmd) {
    switch (cmd) {
        case F_GETFD:
        case F_GETFL:
        case F_GETOWN:
#ifdef F_GETSIG
        case F_GETSIG:
#endif
#ifdef F_GETLEASE
        case F_GETLEASE:
#endif
#ifdef F_GETPIPE_SZ
        case F_GETPIPE_SZ:
#endif
            return 1;
        default:
            return 0;
    }
}

int fcntl(int fd, int cmd, ...) {
    static int (*real_fcntl)(int, int, ...);
    if (!real_fcntl) real_fcntl = dlsym(RTLD_NEXT, "fcntl");

    if (fcntl_has_no_arg(cmd)) return real_fcntl(fd, cmd);

    va_list ap;
    va_start(ap, cmd);
    unsigned long arg = va_arg(ap, unsigned long);
    va_end(ap);

    int rc = real_fcntl(fd, cmd, arg);
    if (rc == 0 && (cmd == F_SETLK || cmd == F_SETLKW)) {
        struct flock *lock = (struct flock *)arg;
        if (lock) record_event(lock->l_type == F_UNLCK ? 'U' : 'L', fd);
    }
    return rc;
}
WRAP_EOF

if ! gcc -shared -fPIC -O2 /tmp/locktrace.c -o /tmp/locktrace.so -ldl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import random
import secrets
import subprocess
import tempfile
from collections import Counter

import pytest

TOOL = "/home/user/dataset_tool"
ORACLE = "/app/sensor_parser"


def run_oracle(record, directory):
    path = os.path.join(directory, "oracle_" + secrets.token_hex(8) + ".txt")
    with open(path, "w", newline="") as f:
        f.write(record)
    try:
        return subprocess.run([ORACLE, path], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=5).returncode
    finally:
        os.unlink(path)


def parse_records(text):
    records = []
    current = None
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip("\r")
        if not line.strip():
            continue
        if line == "BEGIN_RECORD":
            assert current is None, f"Nested/interleaved BEGIN_RECORD at line {number}"
            current = [line]
        elif line == "END_RECORD":
            assert current is not None, f"END_RECORD without BEGIN_RECORD at line {number}"
            current.append(line)
            records.append(tuple(current))
            current = None
        else:
            assert current is not None, f"Line {number} is outside a record: {line!r}"
            current.append(line)
    assert current is None, "Output ended with an unclosed record"
    return records


def test_tool_exists_and_executable():
    assert os.path.isfile(TOOL), f"Executable {TOOL} not found. Did you compile your program?"
    assert os.access(TOOL, os.X_OK), f"File {TOOL} is not executable."


def test_source_code_locking():
    source_path = "/home/user/dataset_tool.c"
    assert os.path.isfile(source_path), f"Source file {source_path} not found."
    with open(source_path, "r") as f:
        content = f.read()
    has_flock = "flock" in content
    has_fcntl = "fcntl" in content and ("F_SETLKW" in content or "F_SETLK" in content)
    assert has_flock or has_fcntl, "Source code does not appear to use POSIX file locking (flock or fcntl with F_SETLKW)."


def test_adversarial_corpus_verification():
    evil_dir = "/app/verifier/evil_corpus/"
    clean_dir = "/app/verifier/clean_corpus/"
    assert os.path.isdir(evil_dir), "Evil corpus directory missing."
    assert os.path.isdir(clean_dir), "Clean corpus directory missing."

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = [os.path.basename(f) for f in evil_files
                     if subprocess.run([TOOL, "--verify", f], capture_output=True,
                                       timeout=5).returncode != 1]
    clean_modified = [os.path.basename(f) for f in clean_files
                      if subprocess.run([TOOL, "--verify", f], capture_output=True,
                                        timeout=5).returncode != 0]
    errors = []
    if evil_bypassed:
        errors.append(f"evil files bypassed verification: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"clean files incorrectly rejected: {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)


def test_generated_verification_matches_parser():
    rng = random.Random(secrets.randbits(64))
    with tempfile.TemporaryDirectory() as td:
        cases = []
        for i in range(36):
            lines = ["BEGIN_RECORD", f"TIMESTAMP: {rng.randrange(1, 2**31)}",
                     f"SENSOR_ID: {rng.randrange(1, 100000)}"]
            events = ["STATUS: OK", "OTHER: " + secrets.token_hex(6)]
            for _ in range(rng.randrange(1, 8)):
                events.append(rng.choice([
                    "STATUS: FAULT", "OVERRIDE: TRUE", "STATUS: OK",
                    "OVERRIDE: FALSE", "NOTE: STATUS: FAULT",
                    "STATUS: FAULT ", "OTHER: " + secrets.token_hex(4)
                ]))
            rng.shuffle(events)
            lines.extend(events)
            lines.append("END_RECORD")
            record = "\n".join(lines) + "\n"
            path = os.path.join(td, f"case_{i}_{secrets.token_hex(4)}.record")
            with open(path, "w", newline="") as f:
                f.write(record)
            expected = 0 if run_oracle(record, td) == 0 else 1
            cases.append((path, expected))

        for path, expected in cases:
            result = subprocess.run([TOOL, "--verify", path], capture_output=True,
                                    timeout=5)
            assert result.returncode == expected, (
                f"--verify disagreed with sensor_parser for generated input; "
                f"expected {expected}, got {result.returncode}")


def test_clean_combined_log_validity():
    output_log = "/home/user/dataset/clean_combined.log"
    assert os.path.isfile(output_log), f"Output file {output_log} not found. Did you run the --build command?"
    with open(output_log, "r") as f:
        text = f.read()
    records = parse_records(text)

    for record in records:
        fault = False
        for line in record:
            if line == "STATUS: FAULT":
                fault = True
            elif line == "OVERRIDE: TRUE":
                fault = False
        assert not fault, "Invalid record containing an unoverridden STATUS: FAULT was written"

    expected = Counter({
        ("BEGIN_RECORD", "TIMESTAMP: 1700000010", "SENSOR_ID: 1", "STATUS: OK", "END_RECORD"): 1,
        ("BEGIN_RECORD", "TIMESTAMP: 1700000012", "SENSOR_ID: 3", "STATUS: FAULT", "OVERRIDE: TRUE", "END_RECORD"): 1,
    })
    assert Counter(records) == expected, "clean_combined.log does not contain exactly all valid input records"


def test_generated_build_is_complete_atomic_and_actually_locks():
    rng = random.Random(secrets.randbits(64))
    with tempfile.TemporaryDirectory() as td:
        input_dir = os.path.join(td, "raw")
        os.makedirs(input_dir)
        output = os.path.join(td, "assembled.log")
        trace = os.path.join(td, "locks.trace")
        all_records = []

        for file_index in range(24):
            subdir = os.path.join(input_dir, f"sub_{file_index % 5}")
            os.makedirs(subdir, exist_ok=True)
            payload = []
            for rec_index in range(5):
                lines = [
                    "BEGIN_RECORD",
                    f"TIMESTAMP: {rng.randrange(1000000000, 2000000000)}",
                    f"SENSOR_ID: {file_index * 100 + rec_index}",
                    "TOKEN: " + secrets.token_hex(12),
                ]
                pattern = rng.randrange(6)
                if pattern == 0:
                    lines += ["STATUS: FAULT"]
                elif pattern == 1:
                    lines += ["STATUS: FAULT", "OVERRIDE: TRUE"]
                elif pattern == 2:
                    lines += ["OVERRIDE: TRUE", "STATUS: FAULT"]
                elif pattern == 3:
                    lines += ["STATUS: FAULT", "OVERRIDE: TRUE", "STATUS: FAULT"]
                elif pattern == 4:
                    lines += ["STATUS: OK", "NOTE: STATUS: FAULT"]
                else:
                    lines += ["STATUS: FAULT ", "OVERRIDE: FALSE"]
                lines += ["PAYLOAD: " + (secrets.token_hex(32) * 8), "END_RECORD"]
                record = "\n".join(lines) + "\n"
                all_records.append(record)
                payload.append(record)
            path = os.path.join(subdir, f"capture_{file_index}_{secrets.token_hex(3)}.log.gz")
            with gzip.open(path, "wt", newline="") as gz:
                gz.write("".join(payload))

        expected = Counter()
        for record in all_records:
            if run_oracle(record, td) == 0:
                expected[tuple(record.splitlines())] += 1

        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/locktrace.so"
        env["DATASET_TRACE_OUTPUT"] = output
        env["DATASET_LOCK_TRACE"] = trace
        result = subprocess.run([TOOL, "--build", input_dir, output], env=env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Generated --build failed: {result.stderr}"
        assert os.path.isfile(output), "--build did not create its requested output"

        with open(output, "r") as f:
            actual = Counter(parse_records(f.read()))
        assert actual == expected, "--build did not extract all and only the valid generated records"
        assert sum(actual.values()) > 0, "Generated build unexpectedly produced no records"

        assert os.path.isfile(trace), "No successful POSIX lock operation was observed on the output file"
        events = []
        with open(trace, "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) == 2 and parts[0] in ("L", "U"):
                    events.append((parts[0], parts[1]))
        lockers = {tid for kind, tid in events if kind == "L"}
        assert any(kind == "L" for kind, _ in events), "No output lock acquisition was observed"
        assert any(kind == "U" for kind, _ in events), "No output lock release was observed"
        assert len(lockers) >= 2, "Output locking was not used by multiple concurrent worker contexts"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
