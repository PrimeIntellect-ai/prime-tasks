#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import math
import subprocess
import pytest

SOURCE = '/home/user/clean_data.c'
EXECUTABLE = '/home/user/clean_data'
RAW_DATA = '/home/user/raw_data.bin'
ANOMALIES = '/home/user/anomalies.bin'
REPORT = '/home/user/report.txt'
MMAP_PROBE = '/tmp/mmap_probe.so'
MMAP_MARKER = '/tmp/mmap_used.marker'


def build_mmap_probe():
    probe_source = r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = 0;
    if (!real_mmap)
        real_mmap = dlsym(RTLD_NEXT, "mmap");

    if (fd >= 0) {
        char link_name[64];
        char target[PATH_MAX];
        snprintf(link_name, sizeof(link_name), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link_name, target, sizeof(target) - 1);
        if (n > 0) {
            target[n] = '\0';
            if (strcmp(target, "/home/user/raw_data.bin") == 0) {
                const char *marker = getenv("MMAP_MARKER");
                if (marker) {
                    int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0666);
                    if (out >= 0) {
                        write(out, "1", 1);
                        close(out);
                    }
                }
            }
        }
    }
    return real_mmap(addr, length, prot, flags, fd, offset);
}
'''
    with open('/tmp/mmap_probe.c', 'w', encoding='utf-8') as f:
        f.write(probe_source)
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '/tmp/mmap_probe.c', '-o', MMAP_PROBE, '-ldl'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Failed to build mmap probe: {result.stderr}"


def run_program(timeout=120):
    for path in (ANOMALIES, REPORT, MMAP_MARKER):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['LD_PRELOAD'] = MMAP_PROBE
    env['MMAP_MARKER'] = MMAP_MARKER
    result = subprocess.run(
        [EXECUTABLE], cwd='/home/user', env=env,
        capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Compiled C program failed with exit code {result.returncode}. "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.exists(MMAP_MARKER) and os.path.getsize(MMAP_MARKER) > 0, \
        "The executed program did not mmap /home/user/raw_data.bin."


def parse_report(path):
    report = {}
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if ':' in line:
                key, val = line.split(':', 1)
                report[key.strip()] = float(val.strip())
    return report


def test_compile_and_execute_c_program():
    assert os.path.exists(SOURCE), "C source file '/home/user/clean_data.c' is missing."
    build = subprocess.run(
        ['gcc', '-O3', SOURCE, '-o', EXECUTABLE, '-lm'],
        capture_output=True, text=True
    )
    assert build.returncode == 0, f"clean_data.c did not compile with gcc -O3: {build.stderr}"
    assert os.path.isfile(EXECUTABLE), "Compilation did not create /home/user/clean_data."
    assert os.access(EXECUTABLE, os.X_OK), "Compiled output is not executable."
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Compiled output is not an ELF executable."

    build_mmap_probe()
    run_program()


def test_c_source_exists():
    assert os.path.exists('/home/user/clean_data.c'), "C source file '/home/user/clean_data.c' is missing."


def test_executable_exists():
    assert os.path.exists('/home/user/clean_data'), "Compiled executable '/home/user/clean_data' is missing."


def test_anomalies_binary_exists():
    assert os.path.exists('/home/user/anomalies.bin'), "Anomalies binary '/home/user/anomalies.bin' is missing."


def test_report_exists():
    assert os.path.exists('/home/user/report.txt'), "Report file '/home/user/report.txt' is missing."


def test_mmap_used():
    source_path = '/home/user/clean_data.c'
    if os.path.exists(source_path):
        with open(source_path, 'r', encoding='utf-8') as f:
            content = f.read()
        assert "mmap" in content, "The C program must use memory-mapped I/O (mmap) as per requirements."


def test_data_correctness():
    raw_data_path = '/home/user/raw_data.bin'
    anomalies_path = '/home/user/anomalies.bin'
    report_path = '/home/user/report.txt'

    if not os.path.exists(raw_data_path) or not os.path.exists(anomalies_path) or not os.path.exists(report_path):
        pytest.fail("Required data or output files are missing, cannot verify correctness.")

    with open(raw_data_path, 'rb') as f:
        raw_bytes = f.read()

    num_doubles = len(raw_bytes) // 8
    raw_data = struct.unpack(f'{num_doubles}d', raw_bytes)

    mu = sum(raw_data) / num_doubles
    variance = sum((x - mu) ** 2 for x in raw_data) / num_doubles
    sigma = math.sqrt(variance)

    lower_bound = mu - 3 * sigma
    upper_bound = mu + 3 * sigma
    expected_anomalies = [x for x in raw_data if x < lower_bound or x > upper_bound]

    with open(anomalies_path, 'rb') as f:
        actual_bytes = f.read()

    actual_num = len(actual_bytes) // 8
    actual_anomalies = list(struct.unpack(f'{actual_num}d', actual_bytes))

    assert len(expected_anomalies) == len(actual_anomalies), f"Expected {len(expected_anomalies)} anomalies, got {len(actual_anomalies)}."

    expected_sorted = sorted(expected_anomalies)
    actual_sorted = sorted(actual_anomalies)

    for exp, act in zip(expected_sorted, actual_sorted):
        assert math.isclose(exp, act, rel_tol=1e-5), f"Anomaly mismatch: expected {exp}, got {act}."

    report = {}
    with open(report_path, 'r', encoding='utf-8') as f:
        for line in f:
            if ':' in line:
                key, val = line.split(':', 1)
                report[key.strip()] = float(val.strip())

    assert 'Mean' in report, "Report missing 'Mean' field."
    assert 'StdDev' in report, "Report missing 'StdDev' field."
    assert 'Anomalies' in report, "Report missing 'Anomalies' field."
    assert 'Time_Seconds' in report, "Report missing 'Time_Seconds' field."

    assert math.isclose(report['Mean'], mu, abs_tol=1e-4), f"Reported mean {report['Mean']} is incorrect, expected ~{mu}."
    assert math.isclose(report['StdDev'], sigma, abs_tol=1e-4), f"Reported StdDev {report['StdDev']} is incorrect, expected ~{sigma}."
    assert int(report['Anomalies']) == len(expected_anomalies), f"Reported anomalies count {int(report['Anomalies'])} is incorrect, expected {len(expected_anomalies)}."
    assert report['Time_Seconds'] > 0, "Benchmark time must be strictly greater than 0."


def test_executable_handles_fresh_input():
    backup = '/home/user/raw_data.verifier_backup.bin'
    assert not os.path.exists(backup), "Unexpected verifier backup file already exists."

    values = [20.0 + ((i % 101) - 50) * 0.05 for i in range(200000)]
    values.extend([-500.25, 900.75, 275.5, -310.125])

    mu = sum(values) / len(values)
    variance = sum((x - mu) ** 2 for x in values) / len(values)
    sigma = math.sqrt(variance)
    lower = mu - 3 * sigma
    upper = mu + 3 * sigma
    expected = [x for x in values if x < lower or x > upper]

    os.replace(RAW_DATA, backup)
    restore_result = None
    try:
        with open(RAW_DATA, 'wb') as f:
            f.write(struct.pack(f'{len(values)}d', *values))

        run_program(timeout=30)

        assert os.path.exists(ANOMALIES), "Program did not create anomalies.bin for fresh input."
        assert os.path.exists(REPORT), "Program did not create report.txt for fresh input."
        with open(ANOMALIES, 'rb') as f:
            output = f.read()
        assert len(output) % 8 == 0, "anomalies.bin is not a sequence of doubles."
        actual = list(struct.unpack(f'{len(output) // 8}d', output))
        assert sorted(actual) == sorted(expected), "Executable produced incorrect anomalies for fresh input."

        report = parse_report(REPORT)
        assert math.isclose(report.get('Mean', math.nan), mu, abs_tol=1e-4)
        assert math.isclose(report.get('StdDev', math.nan), sigma, abs_tol=1e-4)
        assert int(report.get('Anomalies', -1)) == len(expected)
        assert report.get('Time_Seconds', 0) > 0
    finally:
        try:
            os.remove(RAW_DATA)
        except FileNotFoundError:
            pass
        os.replace(backup, RAW_DATA)
        env = os.environ.copy()
        env['LD_PRELOAD'] = MMAP_PROBE
        env['MMAP_MARKER'] = MMAP_MARKER
        restore_result = subprocess.run(
            [EXECUTABLE], cwd='/home/user', env=env,
            capture_output=True, text=True, timeout=120
        )

    assert restore_result.returncode == 0, "Program failed when restoring outputs for the original dataset."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
