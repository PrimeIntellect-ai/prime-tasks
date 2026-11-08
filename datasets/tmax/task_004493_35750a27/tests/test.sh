#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

WORKSPACE_DIR = "/home/user/workspace/async_engine"
BUG_REPORT_PATH = "/home/user/workspace/bug_report.txt"
ENGINE_CPP_PATH = os.path.join(WORKSPACE_DIR, "engine.cpp")
TEST_CPP_PATH = os.path.join(WORKSPACE_DIR, "test_cancellation.cpp")


def test_make_test_passes():
    """Verify that `make test` rebuilds and completes successfully."""
    for name in ("engine.o", "test_cancellation.o", "test_cancellation"):
        path = os.path.join(WORKSPACE_DIR, name)
        if os.path.exists(path):
            os.remove(path)

    try:
        result = subprocess.run(
            ["make", "test"],
            cwd=WORKSPACE_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        assert result.returncode == 0, "`make test` did not exit with code 0."
        assert "Test passed" in result.stdout, "Expected 'Test passed' in the output of `make test`."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"`make test` failed to run successfully.\nStdout: {e.stdout}\nStderr: {e.stderr}")


def test_engine_average_behavior():
    """Compile engine.cpp directly and exercise zero-task and nonzero averages."""
    assert os.path.isfile(ENGINE_CPP_PATH), f"Engine source {ENGINE_CPP_PATH} is missing."
    assert not os.path.islink(ENGINE_CPP_PATH), "engine.cpp must be a regular source file."

    with open(ENGINE_CPP_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"ExecutionEngine\s*::\s*get_average_processing_time\s*\(", source), (
        "engine.cpp must define ExecutionEngine::get_average_processing_time()."
    )

    samples = [secrets.randbelow(1000) + 1 for _ in range(8)]
    values = ", ".join(str(value) for value in samples)
    expected_checks = []
    running_total = 0
    for index, value in enumerate(samples, start=1):
        running_total += value
        expected_checks.append(
            f"engine.add_completed_task({value});\n"
            f"    if (engine.get_average_processing_time() != {running_total // index}) return {20 + index};"
        )

    harness = f'''#include "engine.h"

int main() {{
    {{
        ExecutionEngine engine;
        if (engine.get_average_processing_time() != 0) return 1;
    }}
    {{
        ExecutionEngine engine;
        engine.start(3);
        engine.cancel();
        if (engine.get_average_processing_time() != 0) return 2;
    }}
    {{
        ExecutionEngine engine;
        {' '.join(expected_checks)}
    }}
    return 0;
}}
'''

    with tempfile.TemporaryDirectory() as tmpdir:
        harness_path = os.path.join(tmpdir, "average_harness.cpp")
        binary_path = os.path.join(tmpdir, "average_harness")
        with open(harness_path, "w", encoding="utf-8") as f:
            f.write(harness)

        compiled = subprocess.run(
            [
                "/usr/bin/g++", "-std=c++17", "-Wall", "-Wextra", "-pthread",
                "-I", WORKSPACE_DIR, harness_path, ENGINE_CPP_PATH, "-o", binary_path,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, (
            f"Direct compilation of engine.cpp failed.\nStdout: {compiled.stdout}\nStderr: {compiled.stderr}"
        )

        executed = subprocess.run(
            [binary_path], capture_output=True, text=True, timeout=30
        )
        assert executed.returncode == 0, (
            "ExecutionEngine returned an incorrect average for zero or completed tasks. "
            f"Exit code: {executed.returncode}\nStdout: {executed.stdout}\nStderr: {executed.stderr}"
        )


def test_bug_report_exists_and_content():
    """Verify that bug_report.txt contains the required diagnosis."""
    assert os.path.isfile(BUG_REPORT_PATH), f"Bug report file {BUG_REPORT_PATH} is missing."

    with open(BUG_REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read().lower()

    assert "get_average_processing_time" in content, (
        "The bug report must contain the name of the function where the crash occurred "
        "('get_average_processing_time')."
    )

    has_math_error = bool(re.search(r'divis|zero|0', content))
    assert has_math_error, (
        "The bug report must mention the mathematical/numerical error (e.g., division by zero)."
    )
    assert re.search(r"divis(?:ion|e|or|or)?[^.\n]{0,50}(?:zero|0)|(?:zero|0)[^.\n]{0,50}(?:denominator|divis)", content), (
        "The bug report must explain that the numerical error was division by a zero denominator."
    )
    assert re.search(r"(?:no|zero|0)[^.\n]{0,40}(?:completed\s+)?tasks?|tasks?[^.\n]{0,40}(?:zero|0)", content), (
        "The bug report must connect the zero denominator to having no completed tasks."
    )


def test_test_cancellation_cpp_not_modified():
    """Verify that test_cancellation.cpp was not modified by the user."""
    expected_content = """#include \"engine.h\"
#include <iostream>

int main() {
    ExecutionEngine engine;
    engine.start(4);

    // Immediately cancel without completing any tasks
    engine.cancel();

    // Gather statistics after cancellation
    int avg_time = engine.get_average_processing_time();

    std::cout << \"Test passed. Average time: \" << avg_time << \" ms\" << std::endl;
    return 0;
}
"""
    assert os.path.isfile(TEST_CPP_PATH), f"File {TEST_CPP_PATH} is missing."

    with open(TEST_CPP_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        "You must not modify the test file (`test_cancellation.cpp`)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
