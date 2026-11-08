#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import secrets
import struct
import subprocess
import time
from pathlib import Path


def test_libfastmerge_compiled():
    """Verify that the shared library was compiled and is operational."""
    so_path = "/app/libfastmerge/libfastmerge.so"
    assert os.path.exists(so_path), f"{so_path} was not generated. Check the Makefile fixes."
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{so_path} is not an ELF shared library."

    lib = ctypes.CDLL(so_path)
    merge = lib.merge_buffers
    merge.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    merge.restype = ctypes.c_void_p
    result = merge(b"alpha", b"beta")
    assert result, "merge_buffers returned NULL."
    try:
        assert ctypes.string_at(result) == b"alphabeta", "merge_buffers produced an incorrect result."
    finally:
        libc = ctypes.CDLL(None)
        libc.free.argtypes = [ctypes.c_void_p]
        libc.free(ctypes.c_void_p(result))


def test_organizer_compiled():
    """Verify that the organizer is executable and dynamically linked to libfastmerge."""
    bin_path = "/home/user/organizer"
    assert os.path.exists(bin_path), f"{bin_path} binary is missing. Did you compile organizer.cpp?"
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."

    dynamic = subprocess.check_output(["readelf", "-d", bin_path], text=True, errors="replace")
    assert "libfastmerge.so" in dynamic, "organizer is not dynamically linked against libfastmerge.so."
    symbols = subprocess.check_output(["nm", "-D", bin_path], text=True, errors="replace")
    assert any(" U merge_buffers" in line for line in symbols.splitlines()), \
        "organizer does not import merge_buffers from the shared library."


def _build_call_counter(counter_path):
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

typedef char *(*merge_fn)(const char *, const char *);
static volatile uint64_t *counter = 0;
static merge_fn real_merge = 0;
static pthread_once_t once = PTHREAD_ONCE_INIT;

__attribute__((constructor)) static void setup_counter(void) {
    const char *path = getenv("MERGE_COUNT_FILE");
    if (!path) return;
    int fd = open(path, O_RDWR);
    if (fd < 0) return;
    void *p = mmap(0, sizeof(uint64_t), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (p != MAP_FAILED) counter = (volatile uint64_t *)p;
}

static void find_real_merge(void) {
    real_merge = (merge_fn)dlsym(RTLD_NEXT, "merge_buffers");
}

char *merge_buffers(const char *a, const char *b) {
    if (counter) __sync_fetch_and_add(counter, 1);
    pthread_once(&once, find_real_merge);
    if (!real_merge) return 0;
    return real_merge(a, b);
}
'''
    src = "/tmp/count_merge_calls.c"
    wrapper = "/tmp/count_merge_calls.so"
    with open(src, "w") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", src, "-o", wrapper, "-ldl", "-pthread"],
        check=True,
        capture_output=True,
    )
    with open(counter_path, "wb") as f:
        f.write(struct.pack("Q", 0))
    return wrapper


def _is_valid_request(base, req):
    try:
        a = Path(req["file_A"])
        b = Path(req["file_B"])
        if not a.is_absolute():
            a = base / a
        if not b.is_absolute():
            b = base / b
        a = a.resolve()
        b = b.resolve()
        base_resolved = base.resolve()
        inside_a = os.path.commonpath([str(base_resolved), str(a)]) == str(base_resolved)
        inside_b = os.path.commonpath([str(base_resolved), str(b)]) == str(base_resolved)
        return inside_a and inside_b and a.is_file() and b.is_file(), a, b
    except (KeyError, OSError, ValueError, TypeError):
        return False, None, None


def test_execution_time_and_correctness():
    """Run on a fresh 10,000-request dataset and verify every result and library call."""
    base = Path("/home/user/project_files")
    requests_file = Path("/home/user/requests.json")
    results_file = Path("/home/user/results.jsonl")
    token = secrets.token_hex(8)

    names = []
    for i in range(500):
        name = f"verify_{token}_{i}.log"
        content = (f"Verifier content {token} for file {i}\n" * 10).encode()
        (base / name).write_bytes(content)
        names.append(name)

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    requests = []
    for i in range(10000):
        if rng.random() < 0.05:
            file_a = f"../verify_outside_{token}_{i}.log"
            file_b = names[rng.randrange(len(names))]
        else:
            file_a = names[rng.randrange(len(names))]
            file_b = names[rng.randrange(len(names))]
        requests.append({"job_id": i, "file_A": file_a, "file_B": file_b})
    requests_file.write_text(json.dumps(requests))

    expected = {}
    valid_count = 0
    for req in requests:
        valid, path_a, path_b = _is_valid_request(base, req)
        if valid:
            valid_count += 1
            len_a = len(path_a.read_bytes().split(b"\0", 1)[0])
            len_b = len(path_b.read_bytes().split(b"\0", 1)[0])
            expected[req["job_id"]] = ("success", len_a + len_b)
        else:
            expected[req["job_id"]] = ("invalid", None)

    if results_file.exists():
        results_file.unlink()

    counter_path = f"/tmp/merge_count_{token}.bin"
    wrapper = _build_call_counter(counter_path)
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/app/libfastmerge" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    env["LD_PRELOAD"] = wrapper + (":" + env["LD_PRELOAD"] if env.get("LD_PRELOAD") else "")
    env["MERGE_COUNT_FILE"] = counter_path

    start = time.time()
    res = subprocess.run(["/home/user/organizer"], env=env, capture_output=True)
    runtime = time.time() - start

    assert res.returncode == 0, \
        f"Organizer failed with return code {res.returncode}. stderr: {res.stderr.decode('utf-8', errors='ignore')}"
    assert results_file.exists(), f"{results_file} was not created by the organizer."

    lines = results_file.read_text().splitlines()
    assert len(lines) == 10000, \
        f"Expected 10000 results in {results_file}, got {len(lines)}. Ensure all requests are processed."

    records = []
    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON on line {i+1} in results.jsonl: {line}"
        assert "job_id" in data, f"Missing 'job_id' on line {i+1}"
        assert "status" in data, f"Missing 'status' on line {i+1}"
        assert data["status"] in ["success", "invalid"], f"Invalid status '{data['status']}' on line {i+1}"
        assert "merged_length" in data, f"Missing 'merged_length' on line {i+1}"
        assert isinstance(data["merged_length"], int), f"'merged_length' must be an integer on line {i+1}"
        assert isinstance(data["job_id"], int), f"'job_id' must be an integer on line {i+1}"
        records.append(data)

    ids = [record["job_id"] for record in records]
    assert len(set(ids)) == len(ids), "results.jsonl contains duplicate job IDs."
    assert set(ids) == set(expected), "results.jsonl job IDs do not match requests.json."

    for record in records:
        expected_status, expected_length = expected[record["job_id"]]
        assert record["status"] == expected_status, \
            f"Incorrect status for job {record['job_id']}: expected {expected_status}, got {record['status']}"
        if expected_status == "success":
            assert record["merged_length"] == expected_length, \
                f"Incorrect merged_length for job {record['job_id']}: expected {expected_length}, got {record['merged_length']}"

    with open(counter_path, "rb") as f:
        merge_calls = struct.unpack("Q", f.read(8))[0]
    assert merge_calls == valid_count, \
        f"Expected merge_buffers to be called once for each of {valid_count} valid requests, but observed {merge_calls} calls."

    assert runtime <= 2.0, \
        f"Execution time {runtime:.3f}s exceeded threshold of 2.0s. Ensure your C++ implementation is highly concurrent."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
