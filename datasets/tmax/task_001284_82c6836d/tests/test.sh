#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import secrets
import stat
import subprocess
import tempfile
import pytest

FIXED_SOURCE = "/home/user/app/server_fixed.c"
FIXED_EXECUTABLE = "/home/user/app/server_fixed"


def test_rca_json():
    rca_path = "/home/user/rca.json"
    assert os.path.isfile(rca_path), f"File not found: {rca_path}"

    with open(rca_path, "r") as f:
        try:
            rca_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{rca_path} is not valid JSON")

    assert rca_data.get("bug_function") == "process_metric", "Incorrect 'bug_function' in rca.json"
    assert rca_data.get("first_anomaly_timestamp") == "2024-05-10T03:14:22", "Incorrect 'first_anomaly_timestamp' in rca.json"
    assert rca_data.get("failed_metric_id") == 105, "Incorrect 'failed_metric_id' in rca.json"


def test_server_fixed_c():
    assert os.path.isfile(FIXED_SOURCE), f"File not found: {FIXED_SOURCE}"

    with open(FIXED_SOURCE, "r") as f:
        content = f.read()

    assert "pthread_mutex_unlock" in content, "Missing pthread_mutex_unlock in server_fixed.c"
    unlock_count = content.count("pthread_mutex_unlock(&state_mutex);")
    assert unlock_count >= 2, "Expected at least 2 pthread_mutex_unlock calls in server_fixed.c to fix the deadlock"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "server_fixed")
        result = subprocess.run(
            ["gcc", "-pthread", FIXED_SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"server_fixed.c does not compile:\n{result.stderr}"


def test_server_fixed_executable():
    assert os.path.isfile(FIXED_EXECUTABLE), f"Executable not found: {FIXED_EXECUTABLE}"

    st = os.stat(FIXED_EXECUTABLE)
    assert bool(st.st_mode & stat.S_IXUSR), f"File is not executable: {FIXED_EXECUTABLE}"

    with open(FIXED_EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server_fixed is not a compiled ELF executable"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "server_fixed")
        result = subprocess.run(
            ["gcc", "-pthread", FIXED_SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"server_fixed.c does not compile:\n{result.stderr}"
        assert filecmp.cmp(FIXED_EXECUTABLE, rebuilt, shallow=False), (
            "server_fixed is not the executable produced from the submitted server_fixed.c "
            "using the required gcc command"
        )

    result = subprocess.run(
        [FIXED_EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3,
    )
    assert result.returncode == 0, f"server_fixed exited unsuccessfully: {result.stderr}"
    assert "Server running..." in result.stdout, "server_fixed did not run the submitted server program"


def test_convergence_failure_does_not_deadlock():
    moderate_id = secrets.randbelow(900000) + 1000
    failed_id = moderate_id + 1
    following_id = moderate_id + 2
    moderate_value = float(secrets.randbelow(800) + 101)
    failed_value = float(secrets.randbelow(5000) + 1001)
    following_value = float(secrets.randbelow(99) + 1)
    expected = moderate_value + following_value

    harness = r'''
#include <stdio.h>

extern void process_metric(int metric_id, double value);
extern double global_aggregate;

static double absolute_value(double value) {
    return value < 0.0 ? -value : value;
}

int main(void) {
    process_metric(@MODERATE_ID@, @MODERATE_VALUE@);
    if (absolute_value(global_aggregate - @MODERATE_VALUE@) > 0.000001) return 10;

    process_metric(@FAILED_ID@, @FAILED_VALUE@);
    if (absolute_value(global_aggregate - @MODERATE_VALUE@) > 0.000001) return 11;

    process_metric(@FOLLOWING_ID@, @FOLLOWING_VALUE@);
    if (absolute_value(global_aggregate - @EXPECTED@) > 0.000001) return 12;

    return 0;
}
'''
    replacements = {
        "@MODERATE_ID@": str(moderate_id),
        "@FAILED_ID@": str(failed_id),
        "@FOLLOWING_ID@": str(following_id),
        "@MODERATE_VALUE@": repr(moderate_value),
        "@FAILED_VALUE@": repr(failed_value),
        "@FOLLOWING_VALUE@": repr(following_value),
        "@EXPECTED@": repr(expected),
    }
    for token, value in replacements.items():
        harness = harness.replace(token, value)

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.c")
        object_path = os.path.join(td, "server_fixed.o")
        test_program = os.path.join(td, "behavior_test")
        with open(harness_path, "w") as f:
            f.write(harness)

        compile_source = subprocess.run(
            ["gcc", "-pthread", "-Dmain=server_submission_main", "-c", FIXED_SOURCE, "-o", object_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compile_source.returncode == 0, f"Could not compile server_fixed.c for testing:\n{compile_source.stderr}"

        compile_harness = subprocess.run(
            ["gcc", "-pthread", harness_path, object_path, "-o", test_program],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compile_harness.returncode == 0, f"Could not link behavioral test:\n{compile_harness.stderr}"

        try:
            result = subprocess.run(
                [test_program],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=3,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("server_fixed.c deadlocked after a convergence failure")

        assert result.returncode == 0, (
            "server_fixed.c did not preserve the aggregate and continue processing after "
            f"a convergence failure (exit code {result.returncode})\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
