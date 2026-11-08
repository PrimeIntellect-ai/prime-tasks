#!/bin/bash
mkdir -p /logs/verifier

cat << 'AUDIT_EOF' > /tmp/queryengine_audit.cpp
#include <cstdio>
#include <cstdlib>
#include <cstring>

static unsigned long fast_calls = 0;
static unsigned long deep_calls = 0;

extern "C" bool match_log_fast(const char* line) {
    ++fast_calls;
    return line != nullptr && std::strstr(line, "ERROR") != nullptr;
}

extern "C" bool match_log_deep(const char* line) {
    ++deep_calls;
    return line != nullptr && std::strstr(line, "ERROR") != nullptr;
}

__attribute__((destructor)) static void write_audit_counts() {
    const char* path = std::getenv("QUERYENGINE_AUDIT_FILE");
    if (!path) return;
    FILE* output = std::fopen(path, "w");
    if (!output) return;
    std::fprintf(output, "%lu %lu\n", fast_calls, deep_calls);
    std::fclose(output);
}
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import time
import uuid
import pytest

TARGET = "/app/fast-log-grep/build/fast-log-grep"
MASSIVE_LOG = "/app/test_data/massive_log.txt"
AUDIT_LIBRARY = "/tmp/libqueryengine_audit.so"


def assert_valid_executable():
    assert os.path.exists(TARGET), f"Executable not found at {TARGET}"
    assert os.path.isfile(TARGET), f"Path {TARGET} is not a file"
    assert os.access(TARGET, os.X_OK), f"Executable {TARGET} is not executable"

    with open(TARGET, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "Final executable is not a compiled ELF binary"

    dynamic_info = subprocess.run(
        ["readelf", "-d", TARGET], capture_output=True, text=True, check=True
    ).stdout
    assert "libqueryengine.so" in dynamic_info, "Executable is not linked to libqueryengine.so"


def test_query_accuracy_and_library_integration():
    assert_valid_executable()

    nonce = uuid.uuid4().hex
    lines = []
    for i in range(240):
        if i % 11 == 0:
            lines.append(f'[ERROR] {nonce} line {i} metadata="escaped \\"quote\\""')
        elif i % 17 == 0:
            lines.append(f'[[[[malformed metadata {nonce} line {i} ERROR')
        elif i % 19 == 0:
            lines.append(f'[INFO] {nonce} line {i} lowercase error only')
        else:
            lines.append(f'[INFO] {nonce} line {i} normal entry')

    expected = [line for line in lines if "ERROR" in line]

    with tempfile.TemporaryDirectory() as directory:
        log_path = os.path.join(directory, "edge_cases.log")
        audit_path = os.path.join(directory, "calls.txt")
        with open(log_path, "w", encoding="utf-8") as log_file:
            log_file.write("\n".join(lines) + "\n")

        env = os.environ.copy()
        env["LD_PRELOAD"] = AUDIT_LIBRARY
        env["QUERYENGINE_AUDIT_FILE"] = audit_path
        result = subprocess.run(
            [TARGET, "--query", "ERROR", log_path],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )

        assert result.returncode == 0, (
            f"Executable failed with return code {result.returncode}.\nStderr: {result.stderr}"
        )
        assert result.stdout.splitlines() == expected, (
            "Query output did not exactly contain the matching log lines in input order"
        )
        assert os.path.isfile(audit_path), "Executable did not invoke the query engine"
        with open(audit_path, encoding="utf-8") as audit_file:
            fast_calls, deep_calls = map(int, audit_file.read().split())
        assert fast_calls == len(lines), (
            f"Expected fast query API once per input line; observed {fast_calls} calls for {len(lines)} lines"
        )
        assert deep_calls == 0, f"Slow deep query API was used {deep_calls} times"


def test_fast_log_grep_performance():
    assert_valid_executable()
    assert os.path.exists(MASSIVE_LOG), f"Test log not found at {MASSIVE_LOG}"

    start_time = time.time()
    try:
        result = subprocess.run(
            [TARGET, "--query", "ERROR", MASSIVE_LOG],
            capture_output=True,
            timeout=10,
        )
        end_time = time.time()
    except subprocess.TimeoutExpired:
        pytest.fail("Execution timed out after 10 seconds. Expected execution time <= 0.5 seconds.")

    assert result.returncode == 0, (
        f"Executable failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )

    execution_time = end_time - start_time
    assert execution_time <= 0.5, (
        f"Execution time {execution_time:.3f}s exceeded threshold of 0.5s."
    )
TEST_EOF

if g++ -shared -fPIC -O2 -o /tmp/libqueryengine_audit.so /tmp/queryengine_audit.cpp \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
