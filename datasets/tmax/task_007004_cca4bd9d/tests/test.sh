#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

HOME = "/home/user"
ROUTER = f"{HOME}/router.c"
SCRIPT = f"{HOME}/build_and_test.sh"
EXE = f"{HOME}/test_router"
CALL_LOG = "/tmp/cmp_version_calls.log"

CASES = [
    ("1.0.0", "1.0.0", 0),
    ("2.1.0", "2.0.9", 1),
    ("1.9.0", "1.10.0", -1),
    ("2.0.0", "1.99.9", 1),
]


def instrumented_router(wrong_case=None):
    branches = []
    for index, (v1, v2, expected) in enumerate(CASES):
        result = expected
        if index == wrong_case:
            result = 1 if expected == 0 else 0
        branches.append(
            f'    if (strcmp(v1, "{v1}") == 0 && strcmp(v2, "{v2}") == 0) return {result};'
        )
    return '''#include "router.h"
#include <stdio.h>
#include <string.h>

int cmp_version(const char *v1, const char *v2) {
    FILE *f = fopen("/tmp/cmp_version_calls.log", "a");
    if (f) {
        fprintf(f, "%s|%s\\n", v1, v2);
        fclose(f);
    }
%s
    return 77;
}
''' % "\n".join(branches)


def clear_generated():
    for path in (EXE, f"{HOME}/test_results.log", f"{HOME}/proxy.conf", CALL_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script():
    return subprocess.run(
        [SCRIPT], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )


def read_calls():
    if not os.path.isfile(CALL_LOG):
        return []
    with open(CALL_LOG) as f:
        return [line.rstrip("\n") for line in f]


def assert_generated_log(unit):
    with open(f"{HOME}/test_results.log") as f:
        assert f.read().strip().splitlines() == [f"UNIT: {unit}", "INTEGRATION: OK"]
    with open(f"{HOME}/proxy.conf") as f:
        assert f.read().strip() == "upstream backend { server 127.0.0.1:8080; }"


def test_active_build_and_test_behavior():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable. Did you run chmod +x?"
    source_path = f"{HOME}/test_router.c"
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."
    with open(source_path) as f:
        source = f.read()
    assert re.search(r'^\s*#\s*include\s*[<\"]router\.h[>\"]', source, re.M), "test_router.c must include router.h"
    assert "cmp_version" in source, "test_router.c does not call cmp_version"

    with open(ROUTER) as f:
        original_router = f.read()

    try:
        # Make cmp_version observable, run the submitted build script from a clean
        # state, and then execute the binary independently.
        with open(ROUTER, "w") as f:
            f.write(instrumented_router())
        clear_generated()
        built = run_script()
        assert built.returncode == 0, f"build_and_test.sh failed:\n{built.stdout}\n{built.stderr}"
        assert_generated_log("OK")
        assert os.path.isfile(EXE), "build_and_test.sh did not create /home/user/test_router"
        assert os.access(EXE, os.X_OK), "/home/user/test_router is not executable"
        with open(EXE, "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/test_router is not a compiled ELF executable"

        if os.path.exists(CALL_LOG):
            os.remove(CALL_LOG)
        direct = subprocess.run([EXE], text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
        assert direct.returncode == 0, f"test_router failed:\n{direct.stdout}\n{direct.stderr}"
        assert direct.stdout.strip() == "ALL TESTS PASSED", "Successful test program must print exactly ALL TESTS PASSED"
        expected_calls = [f"{a}|{b}" for a, b, _ in CASES]
        assert read_calls() == expected_calls, "test_router must call cmp_version exactly once for each required pair, in the listed order"

        # Each required expected result must be asserted: make that one result
        # wrong and require both the program and shell integration to detect it.
        for index, (v1, v2, _) in enumerate(CASES):
            with open(ROUTER, "w") as f:
                f.write(instrumented_router(index))
            clear_generated()
            failed_build = run_script()
            assert failed_build.returncode == 0, "build_and_test.sh must handle a unit-test failure and continue to the integration step"
            assert_generated_log("FAIL")
            assert os.path.isfile(EXE) and os.access(EXE, os.X_OK)

            if os.path.exists(CALL_LOG):
                os.remove(CALL_LOG)
            failed_test = subprocess.run([EXE], text=True, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, timeout=10)
            assert failed_test.returncode != 0, f"test_router did not reject an incorrect result for {v1} versus {v2}"
            assert f"{v1}|{v2}" in read_calls(), f"test_router did not exercise {v1} versus {v2}"
    finally:
        with open(ROUTER, "w") as f:
            f.write(original_router)

    # Leave and verify the final artifacts generated against the supplied router.
    clear_generated()
    final = run_script()
    assert final.returncode == 0, f"Final build_and_test.sh run failed:\n{final.stdout}\n{final.stderr}"
    assert_generated_log("OK")


def test_test_results_log():
    path = "/home/user/test_results.log"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the script?"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert "UNIT: OK" in content, f"{path} does not contain 'UNIT: OK'."
    assert "INTEGRATION: OK" in content, f"{path} does not contain 'INTEGRATION: OK'."


def test_proxy_conf():
    path = "/home/user/proxy.conf"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected = "upstream backend { server 127.0.0.1:8080; }"
    assert content == expected, f"{path} content is incorrect. Expected '{expected}', got '{content}'."


def test_executable_exists():
    path = "/home/user/test_router"
    assert os.path.isfile(path), f"Executable {path} is missing. Did the script compile it?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_build_script_exists_and_executable():
    path = "/home/user/build_and_test.sh"
    assert os.path.isfile(path), f"Script {path} is missing."
    assert os.access(path, os.X_OK), f"Script {path} is not executable. Did you run chmod +x?"


def test_test_router_c_exists():
    path = "/home/user/test_router.c"
    assert os.path.isfile(path), f"Source file {path} is missing."
    with open(path, 'r') as f:
        content = f.read()

    assert "1.0.0" in content, "test_router.c is missing test case for '1.0.0'"
    assert "2.1.0" in content, "test_router.c is missing test case for '2.1.0'"
    assert "2.0.9" in content, "test_router.c is missing test case for '2.0.9'"
    assert "1.9.0" in content, "test_router.c is missing test case for '1.9.0'"
    assert "1.10.0" in content, "test_router.c is missing test case for '1.10.0'"
    assert "2.0.0" in content, "test_router.c is missing test case for '2.0.0'"
    assert "1.99.9" in content, "test_router.c is missing test case for '1.99.9'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
