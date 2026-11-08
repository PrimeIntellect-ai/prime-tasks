#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

SERVICE = "/home/user/sensor_service"
SOURCE = os.path.join(SERVICE, "worker.c")
BINARY = os.path.join(SERVICE, "sensor_sync")
LOG = os.path.join(SERVICE, "sensors.log")
EXPECTED_CRASH = "2023-10-15 03:14:15 [ERROR] FATAL_PAYLOAD_0x8A payload=null"


def run_binary(path, timeout=15):
    return subprocess.run(
        [BINARY, path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=False
    )


def expected_summary(path):
    with open(path, "r", errors="replace") as f:
        count = sum(1 for line in f if "CORRUPT" in line)
    return f"Processing complete. Corrupted packets: {count}\n"


def strip_c_comments_and_strings(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def test_minimal_crash_log():
    crash_log_path = "/home/user/minimal_crash.log"
    assert os.path.isfile(crash_log_path), f"{crash_log_path} does not exist."

    with open(crash_log_path, "r") as f:
        raw = f.read()
        content = raw.strip()

    assert content == EXPECTED_CRASH, f"Content of {crash_log_path} is incorrect. Expected exactly the crashing line."
    assert raw in (EXPECTED_CRASH, EXPECTED_CRASH + "\n"), "minimal_crash.log must contain exactly one line and no extra content."


def test_worker_c_fixes():
    worker_c_path = SOURCE
    assert os.path.isfile(worker_c_path), f"{worker_c_path} does not exist."

    with open(worker_c_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    has_mutex = "pthread_mutex_t" in content and ("pthread_mutex_lock" in content or "pthread_mutex_trylock" in content)
    has_atomic = "_Atomic" in content or "__atomic_" in content or "__sync_" in content
    assert has_mutex or has_atomic, "worker.c does not seem to include a mutex or atomic operation to fix the race condition."

    has_memset = "memset" in content and "tm" in content
    has_zero_init = "= {0}" in content or "= { 0 }" in content
    assert has_memset or has_zero_init, "worker.c does not properly initialize `struct tm` (e.g., using memset or = {0})."

    # Keywords in comments or string literals do not count as fixes.
    code = strip_c_comments_and_strings(content)
    real_mutex = "pthread_mutex_t" in code and re.search(r"\bpthread_mutex_(?:lock|trylock)\s*\(", code)
    real_atomic = re.search(r"\b_Atomic\b|\b__atomic_[A-Za-z0-9_]*\s*\(|\b__sync_[A-Za-z0-9_]*\s*\(", code)
    assert real_mutex or real_atomic, "The synchronization primitive must be present in executable C code."

    real_init = re.search(r"\bstruct\s+tm\s+\w+\s*=\s*\{\s*0\s*\}", code) or re.search(r"\bmemset\s*\(\s*&\s*\w+\s*,\s*0\s*,", code)
    assert real_init, "struct tm must actually be zero-initialized in executable C code."
    assert re.search(r"\.\s*tm_isdst\s*=\s*-\s*1\b", code), "parse_timestamp must request automatic DST determination with tm_isdst = -1."


def test_binary_compiled():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sensor_sync is not a compiled ELF binary."


def test_rebuild_and_timestamp_behavior():
    build = subprocess.run(["make", "-B", "sensor_sync"], cwd=SERVICE, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert build.returncode == 0, f"Rebuilding sensor_sync failed:\n{build.stdout}\n{build.stderr}"

    harness = r'''
#define _XOPEN_SOURCE 700
#define main sensor_service_main
#include "/home/user/sensor_service/worker.c"
#undef main

__attribute__((noinline)) static void poison_tm_stack(void) {
    volatile struct tm value;
    memset((void *)&value, 0xA5, sizeof(value));
    __asm__ __volatile__("" : : "r"(&value) : "memory");
}

static int check_one(const char *tz, const char *stamp) {
    setenv("TZ", tz, 1);
    tzset();
    struct tm expected_tm = {0};
    expected_tm.tm_isdst = -1;
    if (!strptime(stamp, "%Y-%m-%d %H:%M:%S", &expected_tm)) return 10;
    time_t expected = mktime(&expected_tm);
    for (int i = 0; i < 20; ++i) {
        time_t actual = (time_t)-1;
        poison_tm_stack();
        parse_timestamp(stamp, &actual);
        if (actual != expected || actual == (time_t)-1) return 20;
    }
    return 0;
}

int main(void) {
    int rc;
    rc = check_one("EST5EDT,M3.2.0/2,M11.1.0/2", "2023-01-15 03:14:15");
    if (rc) return rc;
    rc = check_one("EST5EDT,M3.2.0/2,M11.1.0/2", "2023-07-15 03:14:15");
    if (rc) return rc;
    return check_one("UTC0", "2023-10-15 03:14:15");
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "timestamp_test.c")
        exe = os.path.join(td, "timestamp_test")
        with open(src, "w") as f:
            f.write(harness)
        compile_result = subprocess.run(
            ["gcc", "-O0", "-pthread", src, "-o", exe], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert compile_result.returncode == 0, f"Could not test parse_timestamp:\n{compile_result.stderr}"
        result = subprocess.run([exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, "parse_timestamp does not reliably initialize struct tm and handle DST."


def test_program_behavior_and_race_fix():
    # Exercise the crash payload and derive each expected count from the input.
    cases = []
    cases.append([
        "2023-01-15 03:14:15 [INFO] ok\n",
        EXPECTED_CRASH + "\n",
        "2023-07-15 03:14:15 [WARN] CORRUPT data\n",
        "2023-10-15 03:14:15 [WARN] CORRUPT data\n",
    ])
    cases.append([
        f"2023-10-15 03:{i % 60:02d}:{i % 60:02d} [WARN] CORRUPT packet={i}\n"
        for i in range(10000)
    ])

    with tempfile.TemporaryDirectory() as td:
        for case_num, lines in enumerate(cases):
            path = os.path.join(td, f"case-{case_num}.log")
            with open(path, "w") as f:
                f.writelines(lines)
            expected = expected_summary(path)
            repetitions = 1 if case_num == 0 else 8
            for _ in range(repetitions):
                result = run_binary(path)
                assert result.returncode == 0, f"sensor_sync failed or crashed: {result.stderr}"
                assert result.stdout == expected, f"Incorrect or racy packet count: expected {expected!r}, got {result.stdout!r}"


def test_success_out():
    success_out_path = "/home/user/success.out"
    assert os.path.isfile(success_out_path), f"{success_out_path} does not exist."

    with open(success_out_path, "r") as f:
        content = f.read()

    assert "Processing complete. Corrupted packets: " in content, f"{success_out_path} does not contain the expected success message."

    result = run_binary(LOG)
    assert result.returncode == 0, f"sensor_sync does not successfully process sensors.log: {result.stderr}"
    expected = expected_summary(LOG)
    assert result.stdout == expected, f"sensor_sync reported the wrong result for sensors.log: {result.stdout!r}"
    assert content == expected, "success.out is not the exact output of a successful run on sensors.log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
