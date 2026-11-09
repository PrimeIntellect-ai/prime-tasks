#!/bin/bash
mkdir -p /logs/verifier

verify_task() {
    python3 - <<'PY' || return 1
import os
import re

source_path = "/home/user/clean_data.cpp"
assert os.path.isfile(source_path), f"Missing required C++ source file: {source_path}"
assert not os.path.islink(source_path), f"C++ source must be a regular file: {source_path}"

with open(source_path, "r", encoding="utf-8", errors="replace") as f:
    source = f.read()

# Remove comments and string/character literals so API names merely printed or
# mentioned in comments do not satisfy the threading requirement.
clean = re.sub(
    r'//.*?$|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
    ' ',
    source,
    flags=re.MULTILINE | re.DOTALL,
)
code_without_directives = re.sub(r'^\s*#.*$', ' ', clean, flags=re.MULTILINE)
uses_thread = bool(re.search(r'\b(?:std\s*::\s*)?thread\b', code_without_directives))
uses_async = bool(re.search(r'\b(?:std\s*::\s*)?async\s*\(', code_without_directives))
uses_parallel_policy = bool(re.search(
    r'\b(?:std\s*::\s*)?execution\s*::\s*par(?:_unseq)?\b|\bstd\s*::\s*execution\s*::\s*unseq\b',
    code_without_directives,
))
assert uses_thread or uses_async or uses_parallel_policy, \
    "clean_data.cpp does not use std::thread, std::async, or a standard parallel execution policy"
PY

    rm -f /home/user/clean_data /home/user/cleaned_long_data.csv
    rm -rf /home/user/reports

    g++ -std=c++17 -pthread /home/user/clean_data.cpp -o /home/user/clean_data || return 1
    test -f /home/user/clean_data && test -x /home/user/clean_data || return 1

    # Audit pthread creation while executing the submitted artifact. This prevents
    # a threading API name in dead code from satisfying the parallelism check.
    cat > /tmp/thread_audit.cpp <<'CPP' || return 1
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdlib>

extern "C" int pthread_create(pthread_t* thread, const pthread_attr_t* attr,
                              void* (*start_routine)(void*), void* arg) {
    using create_fn = int (*)(pthread_t*, const pthread_attr_t*, void* (*)(void*), void*);
    static create_fn real_create = reinterpret_cast<create_fn>(dlsym(RTLD_NEXT, "pthread_create"));
    const char* log_path = std::getenv("THREAD_AUDIT_LOG");
    if (log_path) {
        int fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            const char marker = '1';
            (void)write(fd, &marker, 1);
            close(fd);
        }
    }
    if (!real_create) return -1;
    return real_create(thread, attr, start_routine, arg);
}
CPP
    g++ -std=c++17 -shared -fPIC /tmp/thread_audit.cpp -o /tmp/thread_audit.so -ldl -pthread || return 1
    rm -f /tmp/thread_audit.log
    timeout 30s env LD_PRELOAD=/tmp/thread_audit.so THREAD_AUDIT_LOG=/tmp/thread_audit.log /home/user/clean_data || return 1
    test -s /tmp/thread_audit.log || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py || return 1
import os
import csv
import math
import re


def get_original_data():
    input_file = "/home/user/sensor_data_wide.csv"
    sensors = {}
    with open(input_file, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            sensor_id = row[0]
            values = row[1:]
            sensors[sensor_id] = values
    return sensors


def interpolate_values(values):
    parsed = []
    for v in values:
        if v == 'NaN':
            parsed.append(None)
        else:
            parsed.append(float(v))

    n = len(parsed)
    first_valid_idx = 0
    while first_valid_idx < n and parsed[first_valid_idx] is None:
        first_valid_idx += 1

    if first_valid_idx == n:
        return parsed

    for i in range(first_valid_idx):
        parsed[i] = parsed[first_valid_idx]

    last_valid_idx = n - 1
    while last_valid_idx >= 0 and parsed[last_valid_idx] is None:
        last_valid_idx -= 1

    for i in range(last_valid_idx + 1, n):
        parsed[i] = parsed[last_valid_idx]

    for i in range(first_valid_idx + 1, last_valid_idx):
        if parsed[i] is None:
            next_valid_idx = i + 1
            while parsed[next_valid_idx] is None:
                next_valid_idx += 1

            v_start = parsed[i - 1]
            v_end = parsed[next_valid_idx]
            t_start = i - 1
            t_end = next_valid_idx

            for j in range(i, next_valid_idx):
                parsed[j] = v_start + (v_end - v_start) * (j - t_start) / (t_end - t_start)

    return parsed


def test_cleaned_long_data_exists_and_format():
    output_file = "/home/user/cleaned_long_data.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['sensor_id', 'time_index', 'value'], "Header is incorrect in cleaned_long_data.csv"

        rows = list(reader)
        assert len(rows) == 1000, f"Expected 1000 rows, got {len(rows)}"

    for row_number, row in enumerate(rows, start=2):
        assert len(row) == 3, f"Row {row_number} must contain exactly 3 columns"
        assert re.fullmatch(r'-?\d+\.\d{4}', row[2]), \
            f"Value on row {row_number} is not formatted to exactly 4 decimal places: {row[2]!r}"

    original_data = get_original_data()
    expected_pairs = [(sensor_id, str(time_index))
                      for sensor_id in sorted(original_data)
                      for time_index in range(100)]
    actual_pairs = [(row[0], row[1]) for row in rows]
    assert actual_pairs == expected_pairs, \
        "CSV rows must contain every sensor/time pair exactly once, sorted by sensor_id then time_index"


def test_cleaned_long_data_values():
    output_file = "/home/user/cleaned_long_data.csv"
    original_data = get_original_data()

    expected_data = {}
    for sensor_id, values in original_data.items():
        expected_data[sensor_id] = interpolate_values(values)

    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        next(reader)

        for row in reader:
            sensor_id, time_index, value = row
            time_index = int(time_index)
            value = float(value)

            expected_val = expected_data[sensor_id][time_index]
            assert math.isclose(value, expected_val, abs_tol=1e-3), \
                f"Value mismatch for {sensor_id} at t={time_index}: expected {expected_val:.4f}, got {value:.4f}"


def test_reports_exist_and_content():
    reports_dir = "/home/user/reports/"
    assert os.path.isdir(reports_dir), f"Reports directory {reports_dir} does not exist."

    original_data = get_original_data()

    for sensor_id, values in original_data.items():
        report_file = os.path.join(reports_dir, f"sensor_{sensor_id}_report.txt")
        assert os.path.isfile(report_file), f"Report file {report_file} does not exist."

        interpolated = interpolate_values(values)
        avg_val = sum(interpolated) / len(interpolated)
        max_val = max(interpolated)
        nan_count = sum(1 for v in values if v == 'NaN')

        with open(report_file, 'r') as f:
            content = f.read()

        assert f"Report for Sensor: {sensor_id}" in content, f"Missing or incorrect sensor ID in {report_file}"
        assert "Total Data Points: 100" in content, f"Missing or incorrect total points in {report_file}"
        assert f"Imputed Points: {nan_count}" in content, f"Missing or incorrect imputed points in {report_file}"

        avg_str = f"{avg_val:.4f}"
        max_str = f"{max_val:.4f}"
        assert avg_str[:-1] in content, f"Expected average value ~{avg_str} in {report_file}"
        assert max_str[:-1] in content, f"Expected max value ~{max_str} in {report_file}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if verify_task; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
