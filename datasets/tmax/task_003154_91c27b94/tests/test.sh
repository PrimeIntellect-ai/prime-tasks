#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import subprocess
import tempfile
import pytest

REPO = "/app/vendored/liblog-anomaly"
BINARY = os.path.join(REPO, "anomaly_detector")
SOURCE = os.path.join(REPO, "src/cluster.c")

ORIGINAL_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

void process_line(const char* line) {
    double val = 0.0;
    char* ptr = strstr(line, "cpu_temp=");
    if (ptr) {
        val = atof(ptr + 9);
        double prev_center = -1.0;
        double new_center = val;

        while (prev_center != new_center) {
            prev_center = new_center;
            if (val > 85.3333333 && val < 85.3333334) {
                new_center = (prev_center == val) ? (val + 1e-10) : val;
            } else {
                new_center = val;
            }
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        process_line(line);
    }
    fclose(f);
    return 0;
}
'''

EXPECTED_MAKEFILE = "anomaly_detector: src/cluster.c\n\tgcc -O2 -o anomaly_detector src/cluster.c -lm\n"


def get_api_key_from_git():
    try:
        out = subprocess.check_output(
            ["git", "log", "-p", "--all"], cwd=REPO, text=True
        )
        match = re.search(r'^-\s*#define\s+TEST_API_KEY\s+"([^"]+)"', out, re.MULTILINE)
        if match:
            return match.group(1)
    except Exception:
        pass
    return "A9F3J882MD710X2P"


def get_trigger_log_from_data():
    try:
        with open("/app/data/crash_logs.txt", "r") as f:
            for line in f:
                if "cpu_temp=85.33333333333333" in line:
                    return line.strip()
    except Exception:
        pass
    return "[2023-10-12 14:00:00] ERROR cpu_temp=85.33333333333333"


def normalize_c(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'\s+', '', text)


def run_on_line(binary, line, timeout=2.0):
    fd, path = tempfile.mkstemp(prefix="anomaly-trigger-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(line + "\n")
        return subprocess.run(
            [binary, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    finally:
        os.unlink(path)


def test_api_key_recovered():
    api_key_file = "/home/user/api_key.txt"
    assert os.path.isfile(api_key_file), f"File {api_key_file} does not exist."
    with open(api_key_file, "r") as f:
        key = f.read().strip()
    expected_key = get_api_key_from_git()
    assert key == expected_key, f"Incorrect API Key recovered. Expected {expected_key}, got {key}"


def test_trigger_log_isolated():
    trigger_file = "/home/user/trigger_log.txt"
    assert os.path.isfile(trigger_file), f"File {trigger_file} does not exist."
    with open(trigger_file, "r") as f:
        trigger = f.read().strip()
    expected_trigger = get_trigger_log_from_data()
    assert trigger == expected_trigger, "Failed to isolate the exact trigger log line."


def test_convergence_repair_and_recompiled_binary():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} not found."
    with open(SOURCE, "r") as f:
        source = f.read()

    fixed_loop = re.compile(
        r'while\s*\(\s*fabs\s*\(\s*'
        r'(?:prev_center\s*-\s*new_center|new_center\s*-\s*prev_center)'
        r'\s*\)\s*>\s*(?:1[eE]-5|0\.00001)\s*\)'
    )
    matches = list(fixed_loop.finditer(source))
    assert len(matches) == 1, "The main loop must use fabs(center delta) > 1e-5."

    restored = fixed_loop.sub("while (prev_center != new_center)", source, count=1)
    assert normalize_c(restored) == normalize_c(ORIGINAL_SOURCE), (
        "cluster.c must retain the original detector logic and replace only the "
        "strict convergence test with the requested epsilon test."
    )

    with open(os.path.join(REPO, "Makefile"), "r") as f:
        assert f.read() == EXPECTED_MAKEFILE, "The supplied build recipe was unexpectedly changed."

    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} not found. Did you run 'make'?"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        submitted_binary = f.read()
    assert submitted_binary.startswith(b"\x7fELF"), "anomaly_detector is not a compiled ELF binary."

    trigger = get_trigger_log_from_data()
    try:
        result = run_on_line(BINARY, trigger)
    except subprocess.TimeoutExpired:
        pytest.fail("The submitted binary still hangs on the isolated trigger log.")
    assert result.returncode == 0, f"Binary returned {result.returncode} on the trigger log."

    build = subprocess.run(
        ["make", "-B", "anomaly_detector"],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Recompilation failed:\n{build.stdout}"
    with open(BINARY, "rb") as f:
        rebuilt_binary = f.read()
    assert submitted_binary == rebuilt_binary, (
        "The submitted anomaly_detector was not the binary produced from the repaired source by make."
    )


def test_anomaly_detector_runtime():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} not found. Did you run 'make'?"

    start_time = time.time()
    try:
        result = subprocess.run(
            [BINARY, "/app/data/benchmark.log"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Metric threshold failed: binary execution timed out after 5.0 seconds. The infinite loop is likely not fixed.")

    runtime_seconds = time.time() - start_time
    assert result.returncode == 0, f"Binary failed to execute or returned non-zero exit code: {result.returncode}."
    assert runtime_seconds <= 0.5, f"Metric threshold failed: runtime_seconds ({runtime_seconds:.3f}s) > 0.5s"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
