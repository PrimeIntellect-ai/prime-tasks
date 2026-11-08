#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
from collections import defaultdict

import pytest


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission(tmp_path_factory):
    source = "/home/user/process.cpp"
    assert os.path.exists(source), f"Required C++ source file {source} is missing."
    source_stat = os.lstat(source)
    assert stat.S_ISREG(source_stat.st_mode), f"{source} must be a regular file."
    assert source_stat.st_size > 0, f"{source} is empty."

    work = tmp_path_factory.mktemp("build")
    executable = work / "process"
    monitor_source = work / "thread_monitor.c"
    monitor_library = work / "thread_monitor.so"
    marker = work / "parallel.marker"

    monitor_source.write_text(r'''
#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg) {
    static int (*real_pthread_create)(pthread_t *, const pthread_attr_t *,
                                      void *(*)(void *), void *) = 0;
    if (!real_pthread_create) {
        real_pthread_create = dlsym(RTLD_NEXT, "pthread_create");
    }
    if (!real_pthread_create) return -1;
    int rc = real_pthread_create(thread, attr, start_routine, arg);
    if (rc == 0) {
        const char *path = getenv("PROCESS_PARALLEL_MARKER");
        if (path) {
            int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (fd >= 0) {
                write(fd, "1\n", 2);
                close(fd);
            }
        }
    }
    return rc;
}
''')

    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", str(monitor_source),
         "-o", str(monitor_library), "-ldl", "-pthread"],
        check=True, capture_output=True, text=True
    )
    subprocess.run(
        ["g++", "-std=c++17", "-O2", "-pthread", "-fopenmp",
         source, "-o", str(executable)],
        check=True, capture_output=True, text=True
    )

    output = "/home/user/output.csv"
    if os.path.lexists(output):
        os.remove(output)

    env = os.environ.copy()
    env["LD_PRELOAD"] = str(monitor_library)
    env["PROCESS_PARALLEL_MARKER"] = str(marker)
    env["OMP_NUM_THREADS"] = "4"
    env.pop("OMP_THREAD_LIMIT", None)
    subprocess.run(
        [str(executable)], cwd="/home/user", env=env, check=True,
        timeout=30, capture_output=True, text=True
    )

    assert marker.exists() and marker.stat().st_size > 0, (
        "The submitted program did not create any worker threads; "
        "parallel processing is required."
    )


def test_output_exists():
    """Test that the output CSV file exists."""
    path = "/home/user/output.csv"
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.path.getsize(path) > 0, f"{path} is empty."


def test_output_content():
    """Test that the output CSV contains the correct rolling averages and ordering."""
    csv_path = "/home/user/data.csv"
    bin_path = "/home/user/data.bin"
    output_path = "/home/user/output.csv"

    assert os.path.exists(csv_path), f"Input file {csv_path} is missing."
    assert os.path.exists(bin_path), f"Input file {bin_path} is missing."

    records = []

    with open(csv_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            sid, ts, val = line.split(',')
            records.append((int(sid), int(ts), float(val)))

    with open(bin_path, 'rb') as f:
        while True:
            chunk = f.read(20)
            if not chunk:
                break
            sid, ts, val = struct.unpack('<iqd', chunk)
            records.append((sid, ts, val))

    records.sort(key=lambda x: (x[1], x[0]))

    hist = defaultdict(list)
    expected_output = []
    for r in records:
        sid, ts, val = r
        hist[sid].append(val)
        if len(hist[sid]) > 3:
            hist[sid].pop(0)
        avg = sum(hist[sid]) / len(hist[sid])
        expected_output.append(f"{sid},{ts},{avg:.4f}")

    actual_output = []
    with open(output_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                actual_output.append(line)

    assert len(actual_output) == len(expected_output), f"Output record count mismatch. Expected {len(expected_output)}, got {len(actual_output)}."

    for i, (expected, actual) in enumerate(zip(expected_output, actual_output)):
        assert actual == expected, f"Mismatch at line {i+1}. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
