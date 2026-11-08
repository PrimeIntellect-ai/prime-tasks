#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

RESULTS = "/home/user/results.csv"
PATTERN = re.compile(r"^([^,]+),metric=(\d+)$")


def read_results(path=RESULTS):
    assert os.path.isfile(path), f"Results file {path} is missing."
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def validate_exact_results(lines, datasets):
    assert len(lines) == 20 * len(datasets), (
        f"Expected exactly {20 * len(datasets)} lines, found {len(lines)}."
    )
    seen = {dataset: set() for dataset in datasets}
    for line in lines:
        match = PATTERN.match(line)
        assert match, f"Malformed line found: '{line}'"
        dataset = match.group(1)
        metric = int(match.group(2))
        assert dataset in seen, f"Unexpected dataset '{dataset}' found."
        assert 0 <= metric < 20, (
            f"Metric value '{metric}' out of bounds for dataset '{dataset}'."
        )
        assert metric not in seen[dataset], (
            f"Duplicate metric '{metric}' for dataset '{dataset}'."
        )
        seen[dataset].add(metric)
    for dataset, metrics in seen.items():
        assert metrics == set(range(20)), (
            f"Dataset '{dataset}' does not contain each metric 0-19 exactly once."
        )


def test_writer_code():
    path = "/home/user/writer.cpp"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "flock(" in content and "LOCK_EX" in content, "File writer.cpp must contain exclusive file lock 'flock(fd, LOCK_EX)'."
    assert "flock(" in content and "LOCK_UN" in content, "File writer.cpp must contain unlock 'flock(fd, LOCK_UN)'."


def test_writer_compiled():
    path = "/home/user/writer"
    assert os.path.isfile(path), f"Compiled executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_results_csv_content():
    lines = read_results()
    assert len(lines) == 80, f"Expected exactly 80 lines in {RESULTS}, found {len(lines)}."

    expected_datasets = {
        "cifar10_full": 0,
        "glue_benchmark": 0,
        "imagenet_subset_1": 0,
        "wikitext_103": 0,
    }
    metrics_seen = {dataset: set() for dataset in expected_datasets}

    for line in lines:
        match = PATTERN.match(line)
        assert match, f"Malformed line found in {RESULTS}: '{line}'"
        dataset = match.group(1)
        metric = int(match.group(2))
        assert dataset in expected_datasets, f"Unexpected dataset '{dataset}' found in {RESULTS}."
        assert 0 <= metric < 20, f"Metric value '{metric}' out of bounds for dataset '{dataset}'."
        expected_datasets[dataset] += 1
        assert metric not in metrics_seen[dataset], f"Duplicate metric '{metric}' for dataset '{dataset}'."
        metrics_seen[dataset].add(metric)

    for dataset, count in expected_datasets.items():
        assert count == 20, f"Expected 20 lines for '{dataset}', found {count}."
        assert metrics_seen[dataset] == set(range(20)), f"Expected each metric 0-19 exactly once for '{dataset}'."


def build_trace_library():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

static int is_results_fd(int fd) {
    char linkname[64];
    char target[PATH_MAX + 1];
    long n;
    int len = snprintf(linkname, sizeof(linkname), "/proc/self/fd/%d", fd);
    if (len <= 0) return 0;
    n = syscall(SYS_readlink, linkname, target, PATH_MAX);
    if (n < 0) return 0;
    target[n] = '\0';
    return strcmp(target, "/home/user/results.csv") == 0;
}

static void log_event(const char *event) {
    const char *path = getenv("TRACE_LOG");
    if (!path) return;
    int fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    syscall(SYS_write, fd, event, strlen(event));
    syscall(SYS_write, fd, "\n", 1);
    syscall(SYS_close, fd);
}

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = NULL;
    if (!real_flock) real_flock = dlsym(RTLD_NEXT, "flock");
    int watched = is_results_fd(fd);
    int rc = real_flock(fd, operation);
    int saved = errno;
    if (watched && rc == 0) {
        if (operation == LOCK_EX) log_event("EX");
        else if (operation == LOCK_UN) log_event("UN");
        else log_event("OTHER_FLOCK");
    }
    errno = saved;
    return rc;
}

ssize_t write(int fd, const void *buf, size_t count) {
    int watched = is_results_fd(fd);
    ssize_t rc = syscall(SYS_write, fd, buf, count);
    int saved = errno;
    if (watched && rc >= 0) log_event("WRITE");
    errno = saved;
    return rc;
}

int close(int fd) {
    int watched = is_results_fd(fd);
    if (watched) log_event("CLOSE");
    return syscall(SYS_close, fd);
}
'''
    with open("/tmp/flock_trace.c", "w") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/flock_trace.c", "-o", "/tmp/flock_trace.so", "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_instrumented(binary):
    dataset = "trace_" + secrets.token_hex(8)
    open(RESULTS, "w").close()
    open("/tmp/flock_trace.log", "w").close()
    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/flock_trace.so"
    env["TRACE_LOG"] = "/tmp/flock_trace.log"
    completed = subprocess.run(
        [binary, dataset], env=env, timeout=10,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert completed.returncode == 0, f"{binary} failed when executed: {completed.stderr}"
    validate_exact_results(read_results(), {dataset})
    with open("/tmp/flock_trace.log") as f:
        events = [line.strip() for line in f if line.strip()]
    assert events == ["EX"] + ["WRITE"] * 20 + ["UN", "CLOSE"], (
        f"{binary} did not execute an exclusive flock around all writes and unlock before close; events were {events}."
    )


def run_concurrently(binary):
    datasets = ["concurrent_" + secrets.token_hex(8) for _ in range(6)]
    open(RESULTS, "w").close()
    processes = [subprocess.Popen([binary, dataset]) for dataset in datasets]
    for process in processes:
        assert process.wait(timeout=15) == 0, f"{binary} failed during concurrent execution."

    lines = read_results()
    validate_exact_results(lines, set(datasets))

    # Holding LOCK_EX for the whole loop makes each process's 20-line output one block.
    blocks = []
    for line in lines:
        dataset = PATTERN.match(line).group(1)
        if not blocks or blocks[-1] != dataset:
            blocks.append(dataset)
    assert len(blocks) == len(datasets) and set(blocks) == set(datasets), (
        "Concurrent output was interleaved; the exclusive lock was not held around all 20 writes."
    )


def test_executed_locking_and_output():
    existed = os.path.exists(RESULTS)
    original = open(RESULTS, "rb").read() if existed else None
    try:
        build_trace_library()
        subprocess.run(
            ["g++", "/home/user/writer.cpp", "-o", "/tmp/rebuilt_writer"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        for binary in ("/home/user/writer", "/tmp/rebuilt_writer"):
            run_instrumented(binary)
            run_concurrently(binary)
    finally:
        if existed:
            with open(RESULTS, "wb") as f:
                f.write(original)
        elif os.path.exists(RESULTS):
            os.remove(RESULTS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
