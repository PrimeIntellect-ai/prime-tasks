#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import shutil
import string
import subprocess
import tempfile

import pytest

LIB_PATH = "/home/user/librouter.so"
SOURCE_PATH = "/home/user/router.cpp"
BENCHMARK_PATH = "/home/user/benchmark.py"
RESULTS_PATH = "/home/user/benchmark_results.txt"


def test_required_files_exist():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}"
    assert os.path.isfile(BENCHMARK_PATH), f"Benchmark script not found at {BENCHMARK_PATH}"


def test_symbol_export_no_mangling():
    try:
        output = subprocess.check_output(["nm", "-D", LIB_PATH], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {LIB_PATH}: {e}")

    match = re.search(r'\b[A-Za-z]\s+parse_route\b', output)
    assert match is not None, "Symbol 'parse_route' not found or is mangled in the shared library."


def test_library_correctness():
    try:
        lib = ctypes.CDLL(LIB_PATH)
    except Exception as e:
        pytest.fail(f"Failed to load shared library with ctypes: {e}")

    assert hasattr(lib, "parse_route"), "Function parse_route not found in the shared library."
    parse_route = lib.parse_route
    parse_route.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    parse_route.restype = None

    def check(url):
        path_buf = ctypes.create_string_buffer(256)
        query_buf = ctypes.create_string_buffer(256)
        parse_route(url, path_buf, query_buf)
        expected_path, separator, expected_query = url.partition(b"?")
        if not separator:
            expected_query = b""
        assert path_buf.value == expected_path, (
            f"For {url!r}, expected path {expected_path!r}, got {path_buf.value!r}"
        )
        assert query_buf.value == expected_query, (
            f"For {url!r}, expected query {expected_query!r}, got {query_buf.value!r}"
        )

    # Preserve the original cases.
    check(b"/users/123?active=true")
    check(b"/healthcheck")

    # Exercise first-'?' behavior, empty components, and unpredictable inputs.
    for url in [b"", b"?", b"?only=query", b"/trailing?", b"/a?b?c?d"]:
        check(url)

    alphabet = string.ascii_letters + string.digits + "/_-=&."
    rng = random.SystemRandom()
    for _ in range(30):
        left = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 90)))
        if rng.choice([True, False]):
            right = "".join(rng.choice(alphabet + "?") for _ in range(rng.randint(0, 90)))
            url = (left + "?" + right).encode("ascii")
        else:
            url = left.encode("ascii")
        check(url)


def test_benchmark_results_format():
    assert os.path.isfile(RESULTS_PATH), f"Benchmark results file not found at {RESULTS_PATH}"

    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {RESULTS_PATH}, got {len(lines)}"
    assert lines[0] == "Route: /api/v2/items", f"Line 1 incorrect: {lines[0]}"
    assert lines[1] == "Query: category=books&sort=desc", f"Line 2 incorrect: {lines[1]}"
    time_match = re.match(r"^Time:\s+\d+\.\d+$", lines[2])
    assert time_match is not None, f"Line 3 incorrect format: {lines[2]}"


def test_benchmark_executes_library_100000_times_and_measures_loop():
    with tempfile.TemporaryDirectory() as tmp:
        wrapper_source = os.path.join(tmp, "counting_router.c")
        wrapper_library = os.path.join(tmp, "librouter.so")
        count_file = os.path.join(tmp, "count.txt")
        backup_library = os.path.join(tmp, "submitted_librouter.so")
        sitecustomize = os.path.join(tmp, "sitecustomize.py")

        with open(wrapper_source, "w") as f:
            f.write(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long calls = 0;

void parse_route(const char *url, char *path, char *query) {
    const char *mark;
    size_t path_len;
    calls++;
    mark = strchr(url, '?');
    if (mark) {
        path_len = (size_t)(mark - url);
        memcpy(path, url, path_len);
        path[path_len] = '\0';
        strcpy(query, mark + 1);
    } else {
        strcpy(path, url);
        query[0] = '\0';
    }
}

__attribute__((destructor)) static void write_count(void) {
    const char *filename = getenv("ROUTER_COUNT_FILE");
    if (filename) {
        FILE *out = fopen(filename, "w");
        if (out) {
            fprintf(out, "%lu\n", calls);
            fclose(out);
        }
    }
}
''')

        subprocess.run(
            ["gcc", "-shared", "-fPIC", wrapper_source, "-o", wrapper_library],
            check=True,
            capture_output=True,
            text=True,
        )

        # Give time-module clocks a known elapsed interval. A benchmark that
        # actually takes a start and end reading around the loop reports 12.345.
        with open(sitecustomize, "w") as f:
            f.write('''
import time

def _clock():
    used = [False]
    def read():
        if not used[0]:
            used[0] = True
            return 1000.0
        return 1012.345
    return read

def _clock_ns():
    used = [False]
    def read():
        if not used[0]:
            used[0] = True
            return 1000000000000
        return 1012345000000
    return read

for _name in ("time", "perf_counter", "monotonic", "process_time"):
    if hasattr(time, _name):
        setattr(time, _name, _clock())
for _name in ("time_ns", "perf_counter_ns", "monotonic_ns", "process_time_ns"):
    if hasattr(time, _name):
        setattr(time, _name, _clock_ns())
''')

        shutil.copy2(LIB_PATH, backup_library)
        try:
            shutil.copy2(wrapper_library, LIB_PATH)
            env = os.environ.copy()
            env["ROUTER_COUNT_FILE"] = count_file
            env["PYTHONPATH"] = tmp + os.pathsep + env.get("PYTHONPATH", "")
            completed = subprocess.run(
                ["python3", BENCHMARK_PATH],
                cwd="/home/user",
                env=env,
                text=True,
                capture_output=True,
                timeout=30,
            )
        finally:
            shutil.copy2(backup_library, LIB_PATH)

        assert completed.returncode == 0, (
            f"Benchmark failed with exit code {completed.returncode}: {completed.stderr}"
        )
        assert os.path.isfile(count_file), "Benchmark did not load and call /home/user/librouter.so"
        with open(count_file, "r") as f:
            calls = int(f.read().strip())
        assert calls == 100000, f"Benchmark called parse_route {calls} times, expected 100000"

        lines = completed.stdout.strip().splitlines()
        assert len(lines) == 3, f"Benchmark must print exactly three lines, got: {completed.stdout!r}"
        assert lines[0].strip() == "Route: /api/v2/items"
        assert lines[1].strip() == "Query: category=books&sort=desc"
        match = re.fullmatch(r"Time:\s+(\d+\.\d+)", lines[2].strip())
        assert match is not None, f"Invalid benchmark time line: {lines[2]!r}"
        measured = float(match.group(1))
        assert abs(measured - 12.345) < 0.001, (
            "Benchmark time must be computed from time-module readings around the loop"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
