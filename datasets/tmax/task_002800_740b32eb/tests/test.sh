#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import subprocess
import tempfile
import textwrap
import pytest

def test_leak_report_content():
    report_path = "/home/user/leak_report.txt"
    assert os.path.isfile(report_path), f"File not found: {report_path}"

    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content == "83920", f"leak_report.txt does not contain the correct leaked session ID. Found: '{content}'"

def test_session_manager_cpp_fixed():
    cpp_path = "/home/user/session_manager.cpp"
    assert os.path.isfile(cpp_path), f"File not found: {cpp_path}"

    with open(cpp_path, 'r') as f:
        content = f.read()

    assert "delete" in content, "session_manager.cpp does not contain a 'delete' statement."

    # Extract the handle_disconnect function body roughly
    func_match = re.search(r'void\s+handle_disconnect\s*\([^)]*\)\s*\{(.*?)\n\}', content, re.DOTALL)
    assert func_match, "Could not find 'handle_disconnect' function body."
    func_body = func_match.group(1)

    # Check if delete is in the else block or used unconditionally
    # The original buggy code had:
    # if (graceful) { delete s; } else { ... }

    # Find the else block
    else_match = re.search(r'else\s*\{([^}]+)\}', func_body, re.DOTALL)
    if else_match:
        else_body = else_match.group(1)
        assert "delete " in else_body, "The 'delete' statement was not found in the 'else' block for non-graceful disconnects."
    else:
        # If they refactored to remove the if/else and just delete unconditionally
        assert "delete " in func_body, "The 'delete' statement was not found in the 'handle_disconnect' function."


def test_forceful_disconnect_does_not_leak():
    cpp_path = "/home/user/session_manager.cpp"

    with tempfile.TemporaryDirectory() as tmpdir:
        harness_path = os.path.join(tmpdir, "harness.cpp")
        executable_path = os.path.join(tmpdir, "session_leak_test")

        with open(harness_path, "w") as harness:
            harness.write(textwrap.dedent(r'''
                #include <string>

                void create_session(std::string session_id);
                void handle_disconnect(std::string session_id, bool graceful);

                int main() {
                    for (int i = 0; i < 128; ++i) {
                        std::string id = "forceful_test_" + std::to_string(i);
                        create_session(id);
                        handle_disconnect(id, false);
                    }
                    return 0;
                }
            '''))

        compile_result = subprocess.run(
            [
                "g++", "-std=c++17", "-O0", "-g",
                "-fsanitize=address", "-fno-omit-frame-pointer",
                cpp_path, harness_path, "-o", executable_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compile_result.returncode == 0, (
            "The repaired session_manager.cpp did not compile:\n"
            + compile_result.stdout + compile_result.stderr
        )

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=99"
        env["LSAN_OPTIONS"] = "exitcode=99"
        run_result = subprocess.run(
            [executable_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            "Forceful disconnects still leak memory or trigger a memory error:\n"
            + run_result.stdout + run_result.stderr
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
