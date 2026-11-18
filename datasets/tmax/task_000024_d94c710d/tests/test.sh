#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

BASE_DIR = "/home/user/fast_profiler"
TEST_FILE = os.path.join(BASE_DIR, "tests/test_telemetry.c")
TOKEN_FILE = "/home/user/secret_token.txt"
LOG_FILE = "/home/user/test_result.log"


def recovered_token_from_history():
    commits = subprocess.run(
        ["git", "rev-list", "--all"], cwd=BASE_DIR,
        capture_output=True, text=True, check=True
    ).stdout.splitlines()
    tokens = []
    for commit in commits:
        shown = subprocess.run(
            ["git", "show", f"{commit}:src/telemetry.c"], cwd=BASE_DIR,
            capture_output=True, text=True
        )
        if shown.returncode == 0:
            tokens.extend(re.findall(r'TKN-[A-Za-z0-9-]+', shown.stdout))
    assert tokens, "No historical telemetry token was found in git history."
    return "TKN-883A-29B1" if "TKN-883A-29B1" in tokens else tokens[0]


def test_secret_token_extracted():
    token_file = "/home/user/secret_token.txt"
    assert os.path.isfile(token_file), f"File {token_file} does not exist."

    with open(token_file, "r") as f:
        content = f.read().strip()

    assert content == "TKN-883A-29B1", f"Expected token 'TKN-883A-29B1', but got '{content}'."
    assert content == recovered_token_from_history(), "secret_token.txt does not match the token recovered from git history."


def test_regression_test_file_exists():
    test_file = "/home/user/fast_profiler/tests/test_telemetry.c"
    assert os.path.isfile(test_file), f"File {test_file} does not exist."

    with open(test_file, "r") as f:
        content = f.read()

    assert "telemetry_init" in content, "test_telemetry.c does not contain 'telemetry_init'."
    assert "TELEMETRY_TOKEN" in content, "test_telemetry.c does not contain 'TELEMETRY_TOKEN'."
    assert re.search(r'^\s*#\s*include\s*[<\"]telemetry\.h[>\"]', content, re.MULTILINE), "test_telemetry.c does not include telemetry.h."
    assert re.search(r'\bsetenv\s*\(', content), "test_telemetry.c does not call setenv."


def test_regression_test_behavior():
    token = recovered_token_from_history()
    stub = r'''
#include <stdlib.h>
#include <string.h>
int telemetry_init(void) {
    const char *token = getenv("TELEMETRY_TOKEN");
    const char *result = getenv("VERIFIER_TELEMETRY_RESULT");
    if (token == NULL || strcmp(token, "''' + token + r'''") != 0)
        return -99;
    return result == NULL ? 0 : atoi(result);
}
'''
    with tempfile.TemporaryDirectory() as td:
        stub_path = os.path.join(td, "telemetry_stub.c")
        binary = os.path.join(td, "submitted_test")
        with open(stub_path, "w") as f:
            f.write(stub)
        compiled = subprocess.run(
            ["/usr/bin/gcc", "-Wall", "-Werror", "-Isrc", TEST_FILE, stub_path, "-o", binary],
            cwd=BASE_DIR, capture_output=True, text=True
        )
        assert compiled.returncode == 0, f"Regression test does not compile against telemetry.h:\n{compiled.stdout}\n{compiled.stderr}"

        env = os.environ.copy()
        env["TELEMETRY_TOKEN"] = "WRONG-PRESET-TOKEN"
        env["VERIFIER_TELEMETRY_RESULT"] = "0"
        success = subprocess.run([binary], env=env, capture_output=True, text=True)
        assert success.returncode == 0, "Regression test must return 0 when telemetry_init() returns 0."

        env["TELEMETRY_TOKEN"] = "ANOTHER-WRONG-TOKEN"
        env["VERIFIER_TELEMETRY_RESULT"] = "-7"
        failure = subprocess.run([binary], env=env, capture_output=True, text=True)
        assert failure.returncode == 1, "Regression test must return 1 when telemetry_init() fails."


def test_build_succeeds():
    base_dir = "/home/user/fast_profiler"

    with open(os.path.join(base_dir, "Makefile"), "r") as f:
        makefile = f.read()
    for flag in ["-Wall", "-Werror", "-Wimplicit-function-declaration", "-Isrc"]:
        assert flag in makefile, f"Required existing compiler flag {flag} was removed from the Makefile."

    clean_result = subprocess.run(["make", "clean"], cwd=base_dir, capture_output=True, text=True)
    assert clean_result.returncode == 0, f"'make clean' failed:\n{clean_result.stderr}"

    build_result = subprocess.run(["make", "all"], cwd=base_dir, capture_output=True, text=True)
    assert build_result.returncode == 0, f"'make all' failed:\n{build_result.stderr}"

    assert os.path.isfile(os.path.join(base_dir, "libtelemetry.a")), "libtelemetry.a was not built."


def test_make_test_target():
    base_dir = "/home/user/fast_profiler"
    log_file = "/home/user/test_result.log"

    if os.path.exists(log_file):
        os.remove(log_file)

    test_result = subprocess.run(["make", "test"], cwd=base_dir, capture_output=True, text=True)
    assert test_result.returncode == 0, f"'make test' failed:\n{test_result.stderr}\n{test_result.stdout}"

    assert os.path.isfile(log_file), f"{log_file} was not created by 'make test'."

    with open(log_file, "r") as f:
        content = f.read().strip()

    assert content == "ALL TESTS PASSED", f"Expected 'ALL TESTS PASSED' in log file, but got '{content}'."


def test_make_test_actually_compiles_links_and_runs_test():
    token = recovered_token_from_history()
    source_path = os.path.join(BASE_DIR, "src/telemetry.c")
    with open(source_path, "rb") as f:
        original_source = f.read()

    with tempfile.TemporaryDirectory() as td:
        marker = os.path.join(td, "telemetry_called")
        compiler_log = os.path.join(td, "compiler.log")
        wrapper = os.path.join(td, "gcc")
        with open(wrapper, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$VERIFIER_COMPILER_LOG\"\nexec /usr/bin/gcc \"$@\"\n")
        os.chmod(wrapper, 0o755)

        instrumented = f'''#include "telemetry.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int telemetry_init(void) {{
    const char *token = getenv("TELEMETRY_TOKEN");
    if (token == NULL || strcmp(token, "{token}") != 0)
        return -1;
    FILE *f = fopen("{marker}", "w");
    if (f == NULL)
        return -1;
    fputs("called", f);
    fclose(f);
    return 0;
}}
'''
        env = os.environ.copy()
        env["PATH"] = td + os.pathsep + env.get("PATH", "")
        env["VERIFIER_COMPILER_LOG"] = compiler_log
        env["TELEMETRY_TOKEN"] = "VERIFIER-DECOY"

        try:
            with open(source_path, "w") as f:
                f.write(instrumented)

            clean = subprocess.run(["make", "clean"], cwd=BASE_DIR, env=env, capture_output=True, text=True)
            assert clean.returncode == 0, f"Instrumented make clean failed:\n{clean.stderr}"
            build = subprocess.run(["make", "all"], cwd=BASE_DIR, env=env, capture_output=True, text=True)
            assert build.returncode == 0, f"Instrumented library build failed:\n{build.stdout}\n{build.stderr}"

            open(compiler_log, "w").close()
            if os.path.exists(LOG_FILE):
                os.remove(LOG_FILE)
            run = subprocess.run(["make", "-B", "test"], cwd=BASE_DIR, env=env, capture_output=True, text=True)
            assert run.returncode == 0, f"Forced 'make test' failed:\n{run.stdout}\n{run.stderr}"

            with open(compiler_log, "r") as f:
                invocations = f.read()
            assert "tests/test_telemetry.c" in invocations, "The test target did not compile tests/test_telemetry.c."
            assert "libtelemetry.a" in invocations, "The test target did not link the regression test against libtelemetry.a."
            assert os.path.isfile(marker), "The executable built by the test target did not call telemetry_init()."
            assert os.path.isfile(LOG_FILE), "The test target did not create /home/user/test_result.log after a successful run."
            with open(LOG_FILE, "r") as f:
                assert f.read().strip() == "ALL TESTS PASSED"
        finally:
            with open(source_path, "wb") as f:
                f.write(original_source)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
