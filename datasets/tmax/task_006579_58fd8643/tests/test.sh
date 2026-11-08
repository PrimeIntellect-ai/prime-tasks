#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import stat
import subprocess
import textwrap

APP_DIR = "/home/user/app"
BUILD_SH = os.path.join(APP_DIR, "build.sh")
GCD_CALC = os.path.join(APP_DIR, "gcd_calc")
WRAPPER = os.path.join(APP_DIR, "math_wrapper.py")
PROP_TEST_SH = os.path.join(APP_DIR, "prop_test.sh")
TEST_REPORT_LOG = os.path.join(APP_DIR, "test_report.log")
CALL_LOG = "/tmp/prop_wrapper_calls.log"


def last_nonempty_line(path):
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, f"{path} is empty."
    return lines[-1]


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=20, **kwargs)
    assert result.returncode == 0, (
        f"Command {command!r} failed with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def test_gcd_calc_exists_and_executable():
    assert os.path.exists(GCD_CALC), f"Expected executable {GCD_CALC} does not exist. Did you fix and run build.sh?"
    assert os.path.isfile(GCD_CALC), f"{GCD_CALC} is not a file."
    assert os.access(GCD_CALC, os.X_OK), f"{GCD_CALC} is not executable."


def test_prop_test_sh_exists():
    assert os.path.exists(PROP_TEST_SH), f"Expected script {PROP_TEST_SH} does not exist."
    assert os.path.isfile(PROP_TEST_SH), f"{PROP_TEST_SH} is not a file."


def test_test_report_log_content():
    assert os.path.exists(TEST_REPORT_LOG), f"Expected log file {TEST_REPORT_LOG} does not exist. Did you run prop_test.sh?"
    assert os.path.isfile(TEST_REPORT_LOG), f"{TEST_REPORT_LOG} is not a file."
    assert last_nonempty_line(TEST_REPORT_LOG) == "ALL PROPERTIES PASSED", (
        "Expected log to end with 'ALL PROPERTIES PASSED'."
    )


def test_build_binary_wrapper_and_property_script_behavior():
    assert os.path.isfile(BUILD_SH), f"Expected build script {BUILD_SH} does not exist."
    assert os.path.isfile(WRAPPER), f"Expected Python wrapper {WRAPPER} does not exist."

    # The repaired build script must itself successfully recreate the executable.
    if os.path.exists(GCD_CALC):
        os.remove(GCD_CALC)
    run_checked(["bash", BUILD_SH], cwd=APP_DIR)
    assert os.path.isfile(GCD_CALC), "build.sh did not create gcd_calc."
    assert os.access(GCD_CALC, os.X_OK), "The gcd_calc produced by build.sh is not executable."

    cases = [(1, 1), (48, 18), (270, 192), (997, 991), (1000, 625), (864, 432)]
    for a, b in cases:
        expected = str(math.gcd(a, b))
        native = run_checked([GCD_CALC, str(a), str(b)], cwd=APP_DIR)
        assert native.stdout.strip() == expected, (
            f"gcd_calc({a}, {b}) returned {native.stdout!r}, expected {expected}."
        )
        wrapped = run_checked(["python3", WRAPPER, str(a), str(b)], cwd=APP_DIR)
        assert wrapped.stdout.strip() == expected, (
            f"math_wrapper.py({a}, {b}) returned {wrapped.stdout!r}, expected {expected}."
        )

    wrapper_bytes = open(WRAPPER, "rb").read()
    wrapper_mode = stat.S_IMODE(os.stat(WRAPPER).st_mode)
    report_bytes = open(TEST_REPORT_LOG, "rb").read()

    harness_wrapper = textwrap.dedent("""
        import math
        import os
        import sys

        if len(sys.argv) != 3:
            raise SystemExit(1)
        a = int(sys.argv[1])
        b = int(sys.argv[2])
        with open(os.environ["APP_HARNESS_LOG"], "a") as log:
            log.write(f"{a} {b}\\n")
        value = math.gcd(a, b)
        if os.environ.get("APP_HARNESS_FAULT") == "1":
            value += 1
        print(value)
    """).lstrip()

    try:
        with open(WRAPPER, "w") as f:
            f.write(harness_wrapper)

        env = os.environ.copy()
        env["APP_HARNESS_LOG"] = CALL_LOG
        env.pop("APP_HARNESS_FAULT", None)
        open(CALL_LOG, "w").close()
        if os.path.exists(TEST_REPORT_LOG):
            os.remove(TEST_REPORT_LOG)

        success = subprocess.run(
            ["bash", PROP_TEST_SH], cwd=APP_DIR, env=env,
            capture_output=True, text=True, timeout=30
        )
        assert success.returncode == 0, (
            f"prop_test.sh failed against a correct wrapper. stdout={success.stdout!r}, "
            f"stderr={success.stderr!r}"
        )
        assert os.path.isfile(TEST_REPORT_LOG), "prop_test.sh did not create test_report.log."
        assert last_nonempty_line(TEST_REPORT_LOG) == "ALL PROPERTIES PASSED"

        with open(CALL_LOG) as f:
            calls = [tuple(map(int, line.split())) for line in f if line.strip()]
        assert len(calls) >= 200, (
            "prop_test.sh did not make the wrapper calls needed for 100 pairs and their reversals."
        )
        assert all(1 <= a <= 1000 and 1 <= b <= 1000 for a, b in calls), (
            "prop_test.sh called the wrapper with values outside 1..1000."
        )
        call_set = set(calls)
        assert all((b, a) in call_set for a, b in calls), (
            "Not every tested pair had a corresponding symmetry call with reversed arguments."
        )

        # A symmetric but non-dividing result must be detected immediately rather than
        # allowing the script to self-report success without checking its results.
        env["APP_HARNESS_FAULT"] = "1"
        open(CALL_LOG, "w").close()
        if os.path.exists(TEST_REPORT_LOG):
            os.remove(TEST_REPORT_LOG)
        failed = subprocess.run(
            ["bash", PROP_TEST_SH], cwd=APP_DIR, env=env,
            capture_output=True, text=True, timeout=10
        )
        assert os.path.isfile(TEST_REPORT_LOG), "Failure run did not create test_report.log."
        assert last_nonempty_line(TEST_REPORT_LOG) == "PROPERTY TEST FAILED", (
            "prop_test.sh did not detect a wrapper result that violates divisibility."
        )
        with open(CALL_LOG) as f:
            failure_calls = [line for line in f if line.strip()]
        assert 1 <= len(failure_calls) <= 3, (
            "prop_test.sh did not exit immediately after the first property failure."
        )
    finally:
        with open(WRAPPER, "wb") as f:
            f.write(wrapper_bytes)
        os.chmod(WRAPPER, wrapper_mode)
        with open(TEST_REPORT_LOG, "wb") as f:
            f.write(report_bytes)
        if os.path.exists(CALL_LOG):
            os.remove(CALL_LOG)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
