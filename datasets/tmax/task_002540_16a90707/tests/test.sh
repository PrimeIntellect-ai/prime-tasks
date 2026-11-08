#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/probe_kernel.c
#define _GNU_SOURCE
#include <math.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define MAX_EVENTS 4096
static char event_type[MAX_EVENTS];
static int event_n[MAX_EVENTS];
static int event_count = 0;
static int calls_100 = 0;
static int calls_200 = 0;
static int calls_300 = 0;
static int bad = 0;

static void record_event(char type, int n) {
    if (event_count >= MAX_EVENTS) {
        bad = 1;
        return;
    }
    event_type[event_count] = type;
    event_n[event_count] = n;
    event_count++;
}

int clock_gettime(clockid_t clock_id, struct timespec *tp) {
    if (clock_id == CLOCK_MONOTONIC) {
        record_event('T', 0);
    }
    return (int)syscall(SYS_clock_gettime, clock_id, tp);
}

void kernel_infer(const float *weights, const float *inputs, float *outputs, int n) {
    int *counter = NULL;
    if (n == 100) counter = &calls_100;
    else if (n == 200) counter = &calls_200;
    else if (n == 300) counter = &calls_300;
    else bad = 1;

    record_event('K', n);
    int first = counter && *counter == 0;
    if (counter) (*counter)++;

    if (!weights || !inputs || !outputs) {
        bad = 1;
        return;
    }

    if (first) {
        for (int i = 0; i < n * n; i++) {
            if (fabsf(weights[i] - 0.01f) > 1e-7f) bad = 1;
        }
        for (int i = 0; i < n; i++) {
            if (fabsf(inputs[i] - 0.01f) > 1e-7f) bad = 1;
            if (outputs[i] != 0.0f) bad = 1;
        }
    }

    for (int i = 0; i < n; i++) {
        float sum = 0.0f;
        for (int j = 0; j < n; j++) {
            sum += weights[i * n + j] * inputs[j];
        }
        outputs[i] = sum;
    }

    /* A genuine reference comparison must report this controlled error. */
    if (first) outputs[n - 1] += 0.125f;
}

__attribute__((destructor))
static void write_trace(void) {
    FILE *f = fopen("/tmp/evaluator_trace.txt", "w");
    if (!f) return;
    fprintf(f, "BAD %d\n", bad);
    for (int i = 0; i < event_count; i++) {
        fprintf(f, "%c %d\n", event_type[i], event_n[i]);
    }
    fclose(f);
}
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

BASE = "/home/user/mlops"
REPORT = os.path.join(BASE, "report.csv")
EVALUATOR = os.path.join(BASE, "evaluator.c")


def run(cmd):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=90)


def parse_strict_report(path):
    with open(path, "r") as f:
        raw = f.read()
    lines = raw.splitlines()
    assert len(lines) == 3, f"Expected exactly 3 CSV lines, got {len(lines)}"
    pattern = re.compile(r"^(100|200|300),(\d+\.\d{6}),(\d+\.\d)$")
    parsed = []
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Invalid CSV line: {line!r}"
        parsed.append((match.group(1), match.group(2), match.group(3)))
    assert [row[0] for row in parsed] == ["100", "200", "300"]
    return parsed


def test_evaluator_is_compilable_executable_and_performs_benchmark():
    assert os.path.isfile(EVALUATOR), f"Expected source file {EVALUATOR} does not exist."

    normal_binary = "/tmp/submitted_evaluator"
    probe_binary = "/tmp/submitted_evaluator_probe"
    for path in (normal_binary, probe_binary, REPORT, "/tmp/evaluator_trace.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Compile exactly against the supplied kernel with the requested optimization
    # and math library, then require this fresh executable to generate the report.
    run(["gcc", "-O3", EVALUATOR, os.path.join(BASE, "kernel.c"),
         "-lm", "-o", normal_binary])
    run([normal_binary])
    assert os.path.isfile(REPORT), "Executing evaluator did not generate report.csv"
    normal_report = open(REPORT, "rb").read()
    parse_strict_report(REPORT)

    try:
        os.remove(REPORT)
        # Substitute an instrumented implementation with the same API. It checks
        # initialization, injects a derived accuracy error, and records the exact
        # relationship between monotonic-clock reads and kernel invocations.
        run(["gcc", "-O3", EVALUATOR, "/tmp/probe_kernel.c",
             "-lm", "-o", probe_binary])
        run([probe_binary])
        assert os.path.isfile(REPORT), "Instrumented evaluator did not generate report.csv"
        rows = parse_strict_report(REPORT)
        assert [row[1] for row in rows] == ["0.125000"] * 3, \
            "MAE was not computed from kernel outputs and an independent reference"
        assert all(float(row[2]) > 0 for row in rows), "Measured times must be positive"

        assert os.path.isfile("/tmp/evaluator_trace.txt"), "Missing execution trace"
        with open("/tmp/evaluator_trace.txt") as f:
            trace = [line.strip().split() for line in f if line.strip()]
        assert trace and trace[0] == ["BAD", "0"], \
            "Kernel arguments were not initialized as required"
        events = [(parts[0], int(parts[1])) for parts in trace[1:]]

        expected = []
        for n in (100, 200, 300):
            expected.append(("K", n))       # accuracy invocation
            expected.append(("T", 0))       # benchmark start
            expected.extend([("K", n)] * 1000)
            expected.append(("T", 0))       # benchmark end
        assert events == expected, \
            "Expected one accuracy call and exactly 1,000 consecutive timed kernel calls per N"
    finally:
        # Preserve the report generated using the real supplied kernel.
        with open(REPORT, "wb") as f:
            f.write(normal_report)


def test_evaluator_c_exists():
    """Verify that the evaluator.c source file exists."""
    file_path = "/home/user/mlops/evaluator.c"
    assert os.path.isfile(file_path), f"Expected source file {file_path} does not exist."


def test_report_csv_exists():
    """Verify that the report.csv file was generated."""
    file_path = "/home/user/mlops/report.csv"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."


def test_report_csv_content_and_format():
    """Verify the content and formatting of report.csv."""
    file_path = "/home/user/mlops/report.csv"
    if not os.path.exists(file_path):
        pytest.fail(f"{file_path} is missing.")

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in report.csv, but got {len(lines)}."

    expected_ns = ["100", "200", "300"]
    mae_pattern = re.compile(r"^\d+\.\d{6}$")
    time_pattern = re.compile(r"^\d+\.\d{1}$")

    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 3, f"Line {i+1} does not have exactly 3 columns: '{line}'"
        n_val, mae_str, time_str = parts
        assert n_val == expected_ns[i], f"Expected N={expected_ns[i]} on line {i+1}, got {n_val}."
        assert mae_pattern.match(mae_str), \
            f"MAE on line {i+1} is not formatted to 6 decimal places: '{mae_str}'"
        assert time_pattern.match(time_str), \
            f"Time on line {i+1} is not formatted to 1 decimal place: '{time_str}'"
        try:
            mae_val = float(mae_str)
            time_val = float(time_str)
        except ValueError:
            pytest.fail(f"Non-numeric values found in line {i+1}: '{line}'")
        assert mae_val <= 1e-4, f"MAE on line {i+1} is too high: {mae_val}"
        assert time_val > 0, f"Time on line {i+1} must be positive, got: {time_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
