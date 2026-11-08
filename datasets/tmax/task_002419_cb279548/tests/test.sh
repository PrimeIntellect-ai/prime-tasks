#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'AUDIT_EOF' > /tmp/mmap_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <stdint.h>

static int csv_path_for_fd(int fd, char *buf, size_t size) {
    if (fd < 0 || size < 2) return 0;
    char linkpath[64];
    int n = snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
    if (n <= 0 || (size_t)n >= sizeof(linkpath)) return 0;
    ssize_t got = syscall(SYS_readlinkat, AT_FDCWD, linkpath, buf, size - 1);
    if (got <= 0) return 0;
    buf[got] = '\0';
    size_t len = (size_t)got;
    return len >= 4 && strcmp(buf + len - 4, ".csv") == 0;
}

static void record_event(char kind, int fd) {
    char path[4096];
    if (!csv_path_for_fd(fd, path, sizeof(path))) return;
    const char *marker = getenv("MMAP_AUDIT_MARKER");
    if (!marker || !*marker) return;
    int out = syscall(SYS_openat, AT_FDCWD, marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out < 0) return;
    char line[4200];
    int n = snprintf(line, sizeof(line), "%c %s\n", kind, path);
    if (n > 0) syscall(SYS_write, out, line, (size_t)n);
    syscall(SYS_close, out);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    record_event('M', fd);
    return real_mmap(addr, length, prot, flags, fd, offset);
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *);
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    FILE *result = real_fopen(path, mode);
    if (result) record_event('F', fileno(result));
    return result;
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fopen64)(const char *, const char *);
    if (!real_fopen64) real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    FILE *result = real_fopen64(path, mode);
    if (result) record_event('F', fileno(result));
    return result;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real_fread)(void *, size_t, size_t, FILE *);
    if (!real_fread) real_fread = dlsym(RTLD_NEXT, "fread");
    record_event('R', fileno(stream));
    return real_fread(ptr, size, nmemb, stream);
}

char *fgets(char *s, int size, FILE *stream) {
    static char *(*real_fgets)(char *, int, FILE *);
    if (!real_fgets) real_fgets = dlsym(RTLD_NEXT, "fgets");
    record_event('R', fileno(stream));
    return real_fgets(s, size, stream);
}

ssize_t read(int fd, void *buf, size_t count) {
    static ssize_t (*real_read)(int, void *, size_t);
    if (!real_read) real_read = dlsym(RTLD_NEXT, "read");
    record_event('R', fd);
    return real_read(fd, buf, count);
}
AUDIT_EOF

gcc -shared -fPIC -O2 -o /tmp/mmap_audit.so /tmp/mmap_audit.c -ldl
if [ $? -ne 0 ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import tempfile


def expected_for(json_path, log_files):
    with open(json_path, "r") as f:
        thresholds = json.load(f)

    expected_alerts = []
    for log_file in log_files:
        with open(log_file, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(",")
                if len(parts) == 3:
                    timestamp, mount_point, usage_str = parts
                    try:
                        usage_mb = int(usage_str)
                    except ValueError:
                        continue
                    if mount_point in thresholds:
                        limit_mb = thresholds[mount_point]
                        if usage_mb > limit_mb:
                            expected_alerts.append(
                                f"[{timestamp}] ALERT: {mount_point} exceeded threshold "
                                f"(Current: {usage_mb} MB, Limit: {limit_mb} MB)"
                            )
    return expected_alerts


def test_analyze_c_source_exists_and_uses_mmap():
    source_path = "/home/user/analyze.c"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."

    with open(source_path, "r") as f:
        content = f.read()

    assert "mmap" in content, f"Source file {source_path} does not seem to use 'mmap' as required."


def test_analyze_binary_exists_and_executable():
    binary_path = "/home/user/analyze"
    assert os.path.isfile(binary_path), f"Executable {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."

    with open(binary_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {binary_path} is not an ELF binary."


def test_alerts_log_content():
    json_path = "/home/user/thresholds.json"
    logs_dir = "/home/user/logs"
    alerts_path = "/home/user/alerts.log"

    assert os.path.isfile(json_path), f"Missing {json_path}"
    log_files = sorted(glob.glob(os.path.join(logs_dir, "*.csv")))
    expected_alerts = expected_for(json_path, log_files)

    assert os.path.isfile(alerts_path), f"Output file {alerts_path} does not exist."
    with open(alerts_path, "r") as f:
        actual_alerts = [line.strip() for line in f if line.strip()]

    assert actual_alerts == expected_alerts, (
        f"Contents of {alerts_path} do not match the expected alerts.\n"
        f"Expected:\n{chr(10).join(expected_alerts)}\n"
        f"Actual:\n{chr(10).join(actual_alerts)}"
    )


def test_binary_executes_on_derived_inputs_and_mmaps_each_csv():
    token = secrets.token_hex(8)
    mount_a = f"/audit_{token}/alpha"
    mount_b = f"/audit_{token}/beta"
    missing = f"/audit_{token}/unconfigured"

    with tempfile.TemporaryDirectory(prefix="analyze_verify_") as td:
        config = os.path.join(td, "config.json")
        csv_a = os.path.join(td, "alpha.csv")
        csv_b = os.path.join(td, "beta.csv")
        marker = os.path.join(td, "mmap-events.txt")

        thresholds = {mount_a: 137, mount_b: 9021}
        with open(config, "w") as f:
            json.dump(thresholds, f)
        with open(csv_a, "w") as f:
            f.write(f"2042-01-01 00:00:00,{mount_a},137\n")
            f.write(f"2042-01-01 00:01:00,{mount_a},138\n")
            f.write(f"2042-01-01 00:02:00,{missing},999999\n")
        with open(csv_b, "w") as f:
            f.write(f"2042-01-02 03:04:05,{mount_b},9022\n")
            f.write(f"2042-01-02 03:05:05,{mount_b},9000")

        expected = expected_for(config, [csv_a, csv_b])
        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/mmap_audit.so"
        env["MMAP_AUDIT_MARKER"] = marker
        result = subprocess.run(
            ["/home/user/analyze", config, csv_a, csv_b],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=10,
        )
        assert result.returncode == 0, f"analyze failed: {result.stderr}"
        actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert actual == expected, f"Derived-input output mismatch: {actual!r} != {expected!r}"

        assert os.path.isfile(marker), "No mmap activity was observed while processing CSV files."
        with open(marker, "r") as f:
            events = [line.rstrip("\n") for line in f]
        assert f"M {csv_a}" in events, f"The first CSV was not mmap'ed; events: {events!r}"
        assert f"M {csv_b}" in events, f"The second CSV was not mmap'ed; events: {events!r}"
        forbidden = [e for e in events if e.startswith("F ") or e.startswith("R ")]
        assert not forbidden, f"CSV data was read with forbidden standard/read I/O: {forbidden!r}"

    # Execute the submitted artifact on the provided inputs and make it produce
    # the required final redirected file, rather than trusting a prewritten log.
    json_path = "/home/user/thresholds.json"
    log_files = sorted(glob.glob("/home/user/logs/*.csv"))
    expected = expected_for(json_path, log_files)
    with open("/home/user/alerts.log", "w") as output:
        result = subprocess.run(
            ["/home/user/analyze", json_path] + log_files,
            stdout=output,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    assert result.returncode == 0, f"analyze failed on provided files: {result.stderr}"
    with open("/home/user/alerts.log", "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
if [ $? -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
