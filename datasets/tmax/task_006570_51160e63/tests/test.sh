#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import tempfile
import textwrap
import pytest

PROJECT = "/home/user/project"
APP = os.path.join(PROJECT, "app")


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def test_00_makefile_actually_builds_app():
    makefile = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile), "Makefile not found."
    if os.path.lexists(APP):
        os.remove(APP)
    result = subprocess.run(["make", "-B", "app"], cwd=PROJECT,
                            capture_output=True, text=True, env=clean_env())
    assert result.returncode == 0, f"Makefile failed to build app:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(APP) and os.access(APP, os.X_OK), "Makefile did not produce executable 'app'."


def test_makefile_rpath():
    app_path = "/home/user/project/app"
    assert os.path.exists(app_path), "Executable 'app' not found at /home/user/project/app."

    result = subprocess.run(["readelf", "-d", app_path], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run readelf on app."

    has_rpath = False
    for line in result.stdout.splitlines():
        if ("(RPATH)" in line or "(RUNPATH)" in line) and ("libs" in line or "/home/user/project/libs" in line):
            has_rpath = True
            break
    assert has_rpath, "The executable does not have the correct RPATH or RUNPATH set to point to the libs directory."


def test_app_c_memory_safety():
    app_c_path = "/home/user/project/app.c"
    assert os.path.exists(app_c_path), "app.c not found at /home/user/project/app.c."

    with open(app_c_path, "r") as f:
        content = f.read()

    assert "strcpy" not in content, "app.c still contains 'strcpy', which is unsafe and causes buffer overflow. You should use sscanf directly on the inputs."


def test_compare_semver_general_and_sanitized():
    rng = random.SystemRandom()
    cases = [
        ((2, 1, 0), (2, 1, 0)),
        ((123456, 789012, 345678), (123456, 789012, 345677)),
        ((999999, 0, 1), (1000000, 0, 0)),
        ((7, 654321, 42), (7, 654322, 0)),
    ]
    for _ in range(48):
        a = tuple(rng.randrange(0, 1000001) for _ in range(3))
        b = tuple(rng.randrange(0, 1000001) for _ in range(3))
        cases.append((a, b))
    for _ in range(8):
        a = tuple(rng.randrange(0, 1000001) for _ in range(3))
        cases.append((a, a))

    checks = []
    for a, b in cases:
        av = ".".join(map(str, a))
        bv = ".".join(map(str, b))
        expected = (a > b) - (a < b)
        checks.append(
            f'    check({json.dumps(av)}, {json.dumps(bv)}, {expected});'
        )

    harness = textwrap.dedent("""
        #include <stdio.h>
        #include <stdlib.h>
        int compare_semver(const char *, const char *);
        static void check(const char *a, const char *b, int expected) {
            int got = compare_semver(a, b);
            int sign = (got > 0) - (got < 0);
            if (sign != expected) {
                fprintf(stderr, "compare_semver(%s, %s): sign %d, expected %d\\n",
                        a, b, sign, expected);
                exit(1);
            }
        }
        int main(void) {
    """) + "\n".join(checks) + textwrap.dedent("""
            return 0;
        }
    """)

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "semver_harness.c")
        renamed_obj = os.path.join(td, "app_under_test.o")
        harness_obj = os.path.join(td, "harness.o")
        binary = os.path.join(td, "semver_harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        common = ["-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-O1", "-g"]
        compile_app = subprocess.run(
            ["gcc", *common, "-Dmain=project_app_main", "-c", os.path.join(PROJECT, "app.c"), "-o", renamed_obj],
            capture_output=True, text=True)
        assert compile_app.returncode == 0, f"Could not compile app.c for semantic-version tests:\n{compile_app.stderr}"
        compile_harness = subprocess.run(
            ["gcc", *common, "-c", harness_path, "-o", harness_obj],
            capture_output=True, text=True)
        assert compile_harness.returncode == 0, f"Could not compile semantic-version harness:\n{compile_harness.stderr}"
        link = subprocess.run(
            ["gcc", *common, renamed_obj, harness_obj, "-L" + os.path.join(PROJECT, "libs"),
             "-lalpha", "-lbeta", "-Wl,-rpath," + os.path.join(PROJECT, "libs"), "-o", binary],
            capture_output=True, text=True)
        assert link.returncode == 0, f"Could not link semantic-version harness:\n{link.stderr}"
        run = subprocess.run([binary], capture_output=True, text=True, env=clean_env(), timeout=20)
        assert run.returncode == 0, f"General or memory-safe semantic-version comparison failed:\n{run.stdout}\n{run.stderr}"


def test_app_behavior():
    app_path = "/home/user/project/app"
    assert os.path.exists(app_path), "Executable 'app' not found."

    env = clean_env()

    result1 = subprocess.run([app_path, "2.1.5"], capture_output=True, text=True, env=env)
    assert result1.returncode == 0, f"Expected exit code 0 for version 2.1.5, got {result1.returncode}."

    result2 = subprocess.run([app_path, "1.9.0"], capture_output=True, text=True, env=env)
    assert result2.returncode == 1, f"Expected exit code 1 for version 1.9.0, got {result2.returncode}."

    result3 = subprocess.run([app_path, "10.20.30"], capture_output=True, text=True, env=env)
    assert result3.returncode == 0, f"Expected exit code 0 for version 10.20.30, got {result3.returncode}."

    rng = random.SystemRandom()
    for _ in range(30):
        version = tuple(rng.randrange(0, 1000001) for _ in range(3))
        text = ".".join(map(str, version))
        expected = 0 if version >= (2, 1, 0) else 1
        result = subprocess.run([app_path, text], capture_output=True, text=True, env=env, timeout=5)
        assert result.returncode == expected, f"Incorrect result for generated version {text}: got {result.returncode}, expected {expected}."


def test_test_py_exists_and_passes():
    test_py_path = "/home/user/project/test.py"
    assert os.path.exists(test_py_path), "test.py not found at /home/user/project/test.py."

    result = subprocess.run(["python3", test_py_path], capture_output=True, text=True, cwd="/home/user/project")
    assert result.returncode == 0, f"test.py failed to execute successfully. Output:\n{result.stderr}"
    assert "ALL TESTS PASSED" in result.stdout, "test.py did not print 'ALL TESTS PASSED' to stdout."

    with tempfile.TemporaryDirectory() as td:
        copied_test = os.path.join(td, "test.py")
        shutil.copyfile(test_py_path, copied_test)
        fake_app = os.path.join(td, "app")
        with open(fake_app, "w") as f:
            f.write("""#!/bin/sh
printf '%s\\n' "$1" >> "$TEST_CALL_LOG"
case "$1" in
  2.1.5) code=0 ;;
  1.9.0) code=1 ;;
  10.20.30) code=0 ;;
  *) code=99 ;;
esac
if [ "${BAD_VERSION:-}" = "$1" ]; then
  if [ "$code" -eq 0 ]; then code=1; else code=0; fi
fi
exit "$code"
""")
        os.chmod(fake_app, 0o755)
        log = os.path.join(td, "calls.log")
        env = os.environ.copy()
        env["TEST_CALL_LOG"] = log
        env["PATH"] = td + os.pathsep + env.get("PATH", "")

        baseline = subprocess.run(["python3", copied_test], cwd=td, env=env,
                                  capture_output=True, text=True, timeout=20)
        assert baseline.returncode == 0, "test.py does not pass when the three required app results are correct."
        assert "ALL TESTS PASSED" in baseline.stdout
        with open(log) as f:
            calls = f.read().splitlines()
        for required in ("2.1.5", "1.9.0", "10.20.30"):
            assert required in calls, f"test.py did not execute ./app {required}."

        for bad_version in ("2.1.5", "1.9.0", "10.20.30"):
            env["BAD_VERSION"] = bad_version
            bad = subprocess.run(["python3", copied_test], cwd=td, env=env,
                                 capture_output=True, text=True, timeout=20)
            assert bad.returncode != 0, f"test.py did not assert the required exit code for {bad_version}."


def test_success_log():
    log_path = "/home/user/project/success.log"
    assert os.path.exists(log_path), "success.log not found at /home/user/project/success.log."

    with open(log_path, "r") as f:
        content = f.read()

    assert "Beta library initialized." in content, "success.log is missing the 'Beta library initialized.' output."
    assert "Version OK: 2.1.5" in content, "success.log is missing the 'Version OK: 2.1.5' output."

    actual = subprocess.run([APP], cwd=PROJECT, env=clean_env(), capture_output=True, text=True, timeout=10)
    assert actual.returncode == 0, f"Running ./app with no arguments failed: {actual.stderr}"
    assert content == actual.stdout, "success.log is not the standard output produced by the current ./app with no arguments."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
