#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import pytest

SIM_PROJECT_DIR = "/home/user/sim_project"
INTEGRATOR_SCRIPT = os.path.join(SIM_PROJECT_DIR, "integrator.sh")
RUN_ALL_SCRIPT = os.path.join(SIM_PROJECT_DIR, "run_all.sh")
K_VALUES_FILE = os.path.join(SIM_PROJECT_DIR, "k_values.txt")
RESULTS_FILE = os.path.join(SIM_PROJECT_DIR, "results.txt")
BOOTSTRAP_SCRIPT = os.path.join(SIM_PROJECT_DIR, "bootstrap.sh")
CI_LOG_FILE = os.path.join(SIM_PROJECT_DIR, "ci.log")
TEST_SCRIPT = os.path.join(SIM_PROJECT_DIR, "test.sh")


def run_script(path, *args, timeout=120):
    return subprocess.run(
        [path, *map(str, args)],
        cwd=SIM_PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def test_integrator_script():
    assert os.path.isfile(INTEGRATOR_SCRIPT), f"File {INTEGRATOR_SCRIPT} is missing."
    assert os.access(INTEGRATOR_SCRIPT, os.X_OK), f"File {INTEGRATOR_SCRIPT} is not executable."

    with open(INTEGRATOR_SCRIPT) as f:
        content = f.read()
    assert "0.5" in content, "integrator.sh does not appear to use 0.5 for dt calculation."
    assert "awk" in content, "integrator.sh does not appear to use awk for floating point math."

    expected = {"0.5": "0.0977", "1": "0.0001", "2": "0.0000"}
    for k, answer in expected.items():
        result = run_script(INTEGRATOR_SCRIPT, k, timeout=20)
        assert result.returncode == 0, f"integrator.sh failed for k={k}: {result.stderr}"
        assert result.stderr == "", f"integrator.sh wrote unexpected stderr for k={k}: {result.stderr!r}"
        assert result.stdout == answer + "\n", (
            f"integrator.sh returned {result.stdout!r} for k={k}; expected only {answer!r}."
        )


def test_run_all_script_and_results():
    assert os.path.isfile(RUN_ALL_SCRIPT), f"File {RUN_ALL_SCRIPT} is missing."
    assert os.access(RUN_ALL_SCRIPT, os.X_OK), f"File {RUN_ALL_SCRIPT} is not executable."

    with open(RUN_ALL_SCRIPT) as f:
        content = f.read()
    assert re.search(r"xargs\s+-P\s*4", content), "run_all.sh does not contain 'xargs -P 4'."

    with open(K_VALUES_FILE) as f:
        k_values = [line.strip() for line in f if line.strip()]
    assert len(k_values) == 100, "The supplied k_values.txt must contain 100 values."

    expected = []
    for k in k_values:
        result = run_script(INTEGRATOR_SCRIPT, k, timeout=20)
        assert result.returncode == 0, f"integrator.sh failed for supplied k={k}: {result.stderr}"
        assert re.fullmatch(r"-?(?:\d+)\.\d{4}\n", result.stdout), (
            f"integrator.sh did not emit one four-decimal value for k={k}: {result.stdout!r}"
        )
        expected.append(result.stdout.strip())

    temp_dir = tempfile.mkdtemp(prefix="verifier-integrator-")
    real_copy = os.path.join(temp_dir, "integrator.real")
    state = os.path.join(temp_dir, "active")
    maximum = os.path.join(temp_dir, "maximum")
    lock = os.path.join(temp_dir, "lock")
    original_mode = os.stat(INTEGRATOR_SCRIPT).st_mode
    shutil.copy2(INTEGRATOR_SCRIPT, real_copy)
    with open(state, "w") as f:
        f.write("0\n")
    with open(maximum, "w") as f:
        f.write("0\n")

    wrapper = r'''#!/bin/bash
STATE=__STATE__
MAXIMUM=__MAXIMUM__
LOCK=__LOCK__
REAL=__REAL__
exec 9>>"$LOCK"
flock 9
cur=$(cat "$STATE")
cur=$((cur + 1))
echo "$cur" > "$STATE"
max=$(cat "$MAXIMUM")
if [ "$cur" -gt "$max" ]; then echo "$cur" > "$MAXIMUM"; fi
flock -u 9
sleep 0.08
"$REAL" "$@"
rc=$?
flock 9
cur=$(cat "$STATE")
echo $((cur - 1)) > "$STATE"
flock -u 9
exit "$rc"
'''
    wrapper = (wrapper.replace("__STATE__", shlex.quote(state))
                      .replace("__MAXIMUM__", shlex.quote(maximum))
                      .replace("__LOCK__", shlex.quote(lock))
                      .replace("__REAL__", shlex.quote(real_copy)))

    try:
        with open(INTEGRATOR_SCRIPT, "w") as f:
            f.write(wrapper)
        os.chmod(INTEGRATOR_SCRIPT, 0o755)
        if os.path.exists(RESULTS_FILE):
            os.remove(RESULTS_FILE)
        result = run_script(RUN_ALL_SCRIPT, timeout=180)
        assert result.returncode == 0, f"run_all.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(RESULTS_FILE), f"File {RESULTS_FILE} is missing. Did run_all.sh execute?"
        with open(maximum) as f:
            observed_max = int(f.read().strip())
        assert observed_max == 4, f"run_all.sh reached {observed_max} concurrent integrator jobs, expected exactly 4."
    finally:
        shutil.copy2(real_copy, INTEGRATOR_SCRIPT)
        os.chmod(INTEGRATOR_SCRIPT, original_mode)
        shutil.rmtree(temp_dir, ignore_errors=True)

    with open(RESULTS_FILE) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 100, f"{RESULTS_FILE} should contain exactly 100 lines, found {len(lines)}."
    for line in lines:
        try:
            float(line)
        except ValueError:
            pytest.fail(f"Line {line!r} in {RESULTS_FILE} is not a valid float.")
    assert collections.Counter(lines) == collections.Counter(expected), (
        "results.txt is not the set of outputs produced by integrator.sh for the supplied k values."
    )


def test_bootstrap_script_and_ci_log():
    assert os.path.isfile(BOOTSTRAP_SCRIPT), f"File {BOOTSTRAP_SCRIPT} is missing."
    assert os.access(BOOTSTRAP_SCRIPT, os.X_OK), f"File {BOOTSTRAP_SCRIPT} is not executable."
    with open(BOOTSTRAP_SCRIPT) as f:
        content = f.read()
    assert "1000" in content, "bootstrap.sh does not specify the required 1000 iterations."

    with open(RESULTS_FILE, "w") as f:
        for i in range(100):
            f.write("1.0000\n" if i < 50 else "3.0000\n")
    if os.path.exists(CI_LOG_FILE):
        os.remove(CI_LOG_FILE)

    result = run_script(BOOTSTRAP_SCRIPT, timeout=180)
    assert result.returncode == 0, f"bootstrap.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    assert os.path.isfile(CI_LOG_FILE), f"File {CI_LOG_FILE} is missing. Did bootstrap.sh execute?"

    with open(CI_LOG_FILE) as f:
        ci = f.read().strip()
    match = re.fullmatch(r"(\d+\.\d{4}),(\d+\.\d{4})", ci)
    assert match, f"{CI_LOG_FILE} does not match the required four-decimal 'lower_bound,upper_bound' format."
    lower, upper = float(match.group(1)), float(match.group(2))
    assert lower <= upper, "Lower bound is greater than upper bound in ci.log."
    assert 1.70 <= lower <= 2.05, f"Bootstrap lower bound {lower} is inconsistent with the test dataset."
    assert 1.95 <= upper <= 2.30, f"Bootstrap upper bound {upper} is inconsistent with the test dataset."


def test_regression_test_script():
    assert os.path.isfile(TEST_SCRIPT), f"File {TEST_SCRIPT} is missing."
    assert os.access(TEST_SCRIPT, os.X_OK), f"File {TEST_SCRIPT} is not executable."

    cases = [
        ("0.0001,4.9999\n", 0),
        ("0.0000,1.0000\n", 1),
        ("1.0000,5.0000\n", 1),
        ("garbage\n", 1),
    ]
    for contents, expected_success in cases:
        with open(CI_LOG_FILE, "w") as f:
            f.write(contents)
        result = run_script(TEST_SCRIPT, timeout=20)
        if expected_success == 0:
            assert result.returncode == 0, f"test.sh rejected valid ci.log {contents.strip()!r}."
        else:
            assert result.returncode != 0, f"test.sh accepted invalid ci.log {contents.strip()!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
