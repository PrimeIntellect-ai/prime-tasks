#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/ci_project")
APP = PROJECT / "app"
LOG = PROJECT / "output.log"


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        **kwargs,
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_submission():
    makefile = PROJECT / "Makefile"
    assert makefile.is_file(), "The project Makefile is missing."

    # Confirm that the effective Make variables contain an explicit modern C++
    # standard flag, rather than relying on the compiler's default standard.
    database = run(["make", "-pn"], cwd=PROJECT).stdout
    flag_values = []
    for name in ("CXXFLAGS", "CPPFLAGS"):
        flag_values.extend(re.findall(rf"^{name}\s*[:+?]?=\s*(.*)$", database, re.MULTILINE))
    effective_flags = " ".join(flag_values)
    assert re.search(r"-std=(?:c|gnu)\+\+(?:1z|17|2a|20|2b|23|26)", effective_flags), (
        "The Makefile does not set an explicit C++17-or-newer standard flag."
    )

    run(["make", "clean"], cwd=PROJECT)
    for path in (APP, LOG, PROJECT / "main.o", PROJECT / "parser.o"):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    run(["make"], cwd=PROJECT)
    assert APP.is_file(), "Running make did not create app."
    assert os.access(APP, os.X_OK), "The app produced by make is not executable."
    assert APP.read_bytes()[:4] == b"\x7fELF", "The app produced by make is not an ELF binary."

    # Run the actual artifact after removing any agent-supplied log.
    LOG.unlink(missing_ok=True)
    run([str(APP)], cwd=PROJECT)

    # Exercise the parser with unpredictable values so a hardcoded application
    # or prewritten output.log is not sufficient.
    target = secrets.token_hex(12)
    user = secrets.token_hex(12)
    harness = Path("/tmp/parser_harness.cpp")
    harness.write_text(r'''
#include <iostream>
#include <string>
#include "parser.h"

int main(int argc, char **argv) {
    if (argc != 3) return 10;
    std::string payload = std::string("CMD:INIT|TARGET:") + argv[1] + "|USER:" + argv[2] + "|";
    auto parsed = parse_payload(payload);
    if (std::string(parsed["TARGET"]) != argv[1]) return 11;
    if (std::string(parsed["USER"]) != argv[2]) return 12;
    return 0;
}
''')
    parser_test = "/tmp/parser_harness"
    sanitizer_flags = [
        "-std=c++17", "-O0", "-g", "-fsanitize=address,undefined",
        "-fsanitize-address-use-after-scope", "-fno-omit-frame-pointer",
    ]
    run([
        "g++", *sanitizer_flags, "-I", str(PROJECT), str(harness),
        str(PROJECT / "parser.cpp"), "-o", parser_test,
    ])
    sanitizer_env = os.environ.copy()
    sanitizer_env["ASAN_OPTIONS"] = "detect_stack_use_after_return=1:halt_on_error=1"
    sanitizer_env["UBSAN_OPTIONS"] = "halt_on_error=1"
    run([parser_test, target, user], env=sanitizer_env)

    # Rebuild the submitted program with sanitizers and execute its real main.
    # The original dangling string_view implementation fails this run even when
    # it happens to print the expected fixed strings in an unsanitized build.
    sanitized_app = "/tmp/ci_project_app_sanitized"
    run([
        "g++", *sanitizer_flags, str(PROJECT / "main.cpp"),
        str(PROJECT / "parser.cpp"), "-o", sanitized_app,
    ])
    LOG.unlink(missing_ok=True)
    run([sanitized_app], cwd=PROJECT, env=sanitizer_env)


def test_app_binary_exists():
    app_path = "/home/user/ci_project/app"
    assert os.path.isfile(app_path), f"The binary {app_path} does not exist. Did you compile the project?"
    assert os.access(app_path, os.X_OK), f"The file {app_path} is not executable."


def test_output_log_exists():
    log_path = "/home/user/ci_project/output.log"
    assert os.path.isfile(log_path), f"The output log {log_path} does not exist. Did you run the compiled app?"


def test_output_log_contents():
    log_path = "/home/user/ci_project/output.log"
    assert os.path.isfile(log_path), f"The output log {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected = "TARGET=PROD\nUSER=ADMIN"

    assert content == expected, (
        f"The contents of {log_path} are incorrect or corrupted.\n"
        f"Expected:\n{expected}\n\nGot:\n{content}\n\n"
        "This indicates the memory lifetime issue was not properly fixed."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
