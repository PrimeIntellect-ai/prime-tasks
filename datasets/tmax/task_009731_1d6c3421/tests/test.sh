#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import subprocess
import tempfile
import textwrap

import pytest

ROOT = "/home/user/migrator"


def run(cmd, cwd=ROOT, timeout=120, env=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )


def test_c_file_fixed():
    """Verify source checks and exercise the C implementation under AddressSanitizer."""
    path = os.path.join(ROOT, "moving_average.c")
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "malloc" in content, "moving_average.c does not appear to use malloc for the return array."
    assert "float result[1000]" not in content, "moving_average.c still contains the buggy stack array 'float result[1000]'."

    harness = r'''
#include "moving_average.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int close_enough(float a, float b) {
    return fabsf(a - b) < 0.0001f;
}

int main(void) {
    float basic[] = {1.0f, 2.0f, 3.0f, 4.0f};
    float *r = moving_average(basic, 4, 2);
    if (!r) return 10;
    if (!close_enough(r[0], 1.5f) || !close_enough(r[1], 2.5f) ||
        !close_enough(r[2], 3.5f)) return 11;
    free(r);

    /* Exceed the old fixed stack buffer and verify every derived result. */
    const int n = 1608;
    const int window = 7;
    float *data = malloc((size_t)n * sizeof(float));
    if (!data) return 12;
    for (int i = 0; i < n; ++i) data[i] = (float)((i % 31) - 15) / 4.0f;

    r = moving_average(data, n, window);
    if (!r) return 13;
    for (int i = 0; i < n - window + 1; ++i) {
        float sum = 0.0f;
        for (int j = 0; j < window; ++j) sum += data[i + j];
        if (!close_enough(r[i], sum / (float)window)) return 14;
    }
    free(r);
    free(data);
    return 0;
}
'''
    harness_path = "/tmp/verify_moving_average.c"
    binary_path = "/tmp/verify_moving_average"
    with open(harness_path, "w") as f:
        f.write(harness)

    compiled = run([
        "gcc", "-std=c11", "-fsanitize=address", "-fno-omit-frame-pointer",
        "-I", ROOT, harness_path, path, "-lm", "-o", binary_path,
    ])
    assert compiled.returncode == 0, (
        f"Could not compile moving_average.c with the C harness.\n"
        f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
    )

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    exercised = run([binary_path], cwd="/tmp", env=env)
    assert exercised.returncode == 0, (
        "The C implementation produced incorrect results or did not return "
        "safely freeable heap memory.\n"
        f"stdout:\n{exercised.stdout}\nstderr:\n{exercised.stderr}"
    )


def test_python_migrated_and_functional():
    """Verify Python 3 syntax and that the migrated integration test really tests the CLI."""
    path = os.path.join(ROOT, "integration.py")
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    try:
        ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"integration.py is not valid Python 3 syntax: {e}")

    # Preserve the original assertion.
    assert 'print "' not in content and "print '" not in content, "integration.py still contains Python 2 style print statements."

    # Run the integration test against controlled good and bad implementations.
    # This rejects an empty script or one that always exits successfully.
    with tempfile.TemporaryDirectory() as td:
        copied_test = os.path.join(td, "integration.py")
        shutil.copy2(path, copied_test)
        fake_cli = os.path.join(td, "ma_cli")

        with open(fake_cli, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' '15.0,25.0,35.0'\n")
        os.chmod(fake_cli, 0o755)
        good = run(["python3", copied_test], cwd=td)
        assert good.returncode == 0, (
            "integration.py rejected the expected CLI result.\n"
            f"stdout:\n{good.stdout}\nstderr:\n{good.stderr}"
        )

        with open(fake_cli, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' '999.0,999.0,999.0'\n")
        os.chmod(fake_cli, 0o755)
        bad = run(["python3", copied_test], cwd=td)
        assert bad.returncode != 0, (
            "integration.py did not fail when ma_cli returned an incorrect result."
        )


def test_go_test_created_and_effective():
    """Verify the requested Go test exists, passes, and detects a broken computation."""
    path = os.path.join(ROOT, "main_test.go")
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "TestComputeMA" in content, "main_test.go does not contain the function TestComputeMA."
    assert "computeMA" in content, "main_test.go does not appear to test the computeMA function."

    tested = run(["go", "test", "-count=1", "./..."])
    assert tested.returncode == 0, (
        f"Go unit tests failed.\nstdout:\n{tested.stdout}\nstderr:\n{tested.stderr}"
    )

    # Temporarily replace the C computation with a compiling but incorrect one.
    # A real TestComputeMA assertion for the required values must then fail.
    c_path = os.path.join(ROOT, "moving_average.c")
    with open(c_path, "r") as f:
        original_c = f.read()
    broken_c = textwrap.dedent('''\
        #include "moving_average.h"
        #include <stdlib.h>
        float* moving_average(float* data, int n, int window) {
            int out_len = n - window + 1;
            if (out_len <= 0) return NULL;
            float *result = malloc((size_t)out_len * sizeof(float));
            if (!result) return NULL;
            for (int i = 0; i < out_len; ++i) result[i] = 0.0f;
            return result;
        }
    ''')
    try:
        with open(c_path, "w") as f:
            f.write(broken_c)
        mutant = run(["go", "test", "-count=1", "./..."])
    finally:
        with open(c_path, "w") as f:
            f.write(original_c)

    assert mutant.returncode != 0, (
        "main_test.go still passed when computeMA was forced to return incorrect values; "
        "TestComputeMA is not effectively asserting the required result."
    )


def test_build_and_test_script():
    """Verify actual build/test orchestration, fail-fast ordering, and final success logging."""
    script_path = os.path.join(ROOT, "build_and_test.sh")
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    log_path = os.path.join(ROOT, "success.log")
    cli_path = os.path.join(ROOT, "ma_cli")
    go_test_path = os.path.join(ROOT, "main_test.go")
    integration_path = os.path.join(ROOT, "integration.py")

    with open(go_test_path, "r") as f:
        original_go_test = f.read()
    with open(integration_path, "r") as f:
        original_integration = f.read()

    # A failing Go test must stop the script after the build and before Python.
    marker = os.path.join(ROOT, ".verifier_python_ran")
    for p in (log_path, cli_path, marker):
        if os.path.exists(p):
            os.remove(p)
    forced_go_failure = textwrap.dedent('''\
        package main
        import "testing"
        func TestComputeMA(t *testing.T) { t.Fatal("forced verifier failure") }
    ''')
    marker_integration = textwrap.dedent(f'''\
        from pathlib import Path
        Path({marker!r}).write_text("ran")
    ''')
    try:
        with open(go_test_path, "w") as f:
            f.write(forced_go_failure)
        with open(integration_path, "w") as f:
            f.write(marker_integration)
        failed_go = run([script_path])
    finally:
        with open(go_test_path, "w") as f:
            f.write(original_go_test)
        with open(integration_path, "w") as f:
            f.write(original_integration)

    assert failed_go.returncode != 0, "build_and_test.sh ignored a failing Go unit test."
    assert os.path.isfile(cli_path) and os.access(cli_path, os.X_OK), (
        "build_and_test.sh did not compile ma_cli before running the Go tests."
    )
    assert not os.path.exists(marker), (
        "build_and_test.sh ran the Python integration test after the Go tests failed."
    )
    assert not os.path.exists(log_path), (
        "build_and_test.sh wrote success.log even though the Go tests failed."
    )

    # A failing Python integration test must also prevent success logging.
    for p in (log_path, cli_path):
        if os.path.exists(p):
            os.remove(p)
    try:
        with open(integration_path, "w") as f:
            f.write("import sys\nsys.exit(23)\n")
        failed_python = run([script_path])
    finally:
        with open(integration_path, "w") as f:
            f.write(original_integration)

    assert failed_python.returncode != 0, "build_and_test.sh ignored a failing Python integration test."
    assert os.path.isfile(cli_path) and os.access(cli_path, os.X_OK), (
        "build_and_test.sh did not build ma_cli before the Python integration test."
    )
    assert not os.path.exists(log_path), (
        "build_and_test.sh wrote success.log even though integration.py failed."
    )

    # Run the unmodified workflow from a clean output state.
    for p in (log_path, cli_path):
        if os.path.exists(p):
            os.remove(p)
    result = run([script_path])
    assert result.returncode == 0, (
        f"build_and_test.sh failed with exit code {result.returncode}.\n"
        f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    )
    assert os.path.isfile(cli_path) and os.access(cli_path, os.X_OK), (
        "build_and_test.sh did not create the executable ma_cli."
    )

    # Exercise the freshly built application on verifier-derived cases.
    cases = [
        ("1.0,2.0,3.0,4.0", "2", "1.5,2.5,3.5"),
        ("2.0,4.0,6.0,8.0,10.0", "3", "4.0,6.0,8.0"),
        ("-2.0,2.0,6.0", "2", "0.0,4.0"),
    ]
    for values, window, expected in cases:
        cli = run([cli_path, values, window])
        assert cli.returncode == 0, f"ma_cli failed for {values} window {window}: {cli.stderr}"
        assert cli.stdout.strip() == expected, (
            f"ma_cli returned {cli.stdout.strip()!r}; expected {expected!r}"
        )

    integration = run(["python3", "integration.py"])
    assert integration.returncode == 0, (
        f"The migrated integration test failed against the built ma_cli.\n"
        f"stdout:\n{integration.stdout}\nstderr:\n{integration.stderr}"
    )
    assert "Integration test PASSED" in integration.stdout, (
        "integration.py did not execute the original integration success check."
    )

    assert os.path.exists(log_path), f"{log_path} was not created by the script."
    with open(log_path, "r") as f:
        log_content = f.read().strip()
    assert log_content == "ALL TESTS PASSED", f"success.log contains unexpected content: '{log_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
