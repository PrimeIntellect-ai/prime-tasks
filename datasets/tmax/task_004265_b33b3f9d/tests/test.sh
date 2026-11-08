#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import time
from decimal import Decimal, InvalidOperation

WORKER = "/home/user/worker_fixed.sh"
REGRESSION = "/home/user/regression.sh"
FUZZ = "/home/user/fuzz.sh"


def assert_executable_file(path):
    assert os.path.isfile(path), f"The file {path} should exist."
    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"The file {path} should be executable."


def expected_decay(value):
    value = Decimal(value)
    threshold = Decimal("0.01")
    while value > threshold:
        value *= Decimal("0.5")
    return value


def parse_decay_output(stdout):
    matches = re.findall(
        r"Decay complete:\s*([^\s]+)", stdout, flags=re.IGNORECASE
    )
    assert matches, f"Worker did not report the final decay value. stdout: {stdout!r}"
    try:
        value = Decimal(matches[-1])
    except InvalidOperation:
        assert False, f"Worker reported a non-numeric decay value: {matches[-1]!r}"
    assert value.is_finite(), f"Worker reported a non-finite value: {value}"
    return value


def test_worker_fixed_exists_and_executable():
    assert_executable_file(WORKER)


def test_worker_fixed_does_not_hang_and_calculates_decay():
    # Exercise the former stagnation point, boundaries, and unrelated values.
    for raw in ["1.0", "0.1", "0.05", "10.0", "3.14159", "0.011", "0.01", "0.0", "-2.5"]:
        try:
            result = subprocess.run(
                [WORKER, raw], capture_output=True, timeout=3, text=True
            )
        except subprocess.TimeoutExpired:
            assert False, f"{WORKER} hung on input {raw}."
        assert result.returncode == 0, (
            f"{WORKER} failed on input {raw} with return code "
            f"{result.returncode}. stderr: {result.stderr}"
        )
        actual = parse_decay_output(result.stdout)
        expected = expected_decay(raw)
        assert actual == expected, (
            f"Incorrect decay for {raw}: expected {expected}, got {actual}. "
            "The worker must repeatedly multiply by 0.5 until the value is at most 0.01."
        )


def test_regression_script():
    assert_executable_file(REGRESSION)
    result = subprocess.run(
        [REGRESSION], capture_output=True, text=True, timeout=8
    )
    assert result.returncode == 0, (
        f"{REGRESSION} did not exit with 0. It exited with "
        f"{result.returncode}. stderr: {result.stderr}"
    )


def test_fuzz_script():
    assert_executable_file(FUZZ)
    try:
        result = subprocess.run(
            [FUZZ], capture_output=True, text=True, timeout=60
        )
    except subprocess.TimeoutExpired:
        assert False, f"{FUZZ} timed out. It should complete all 50 runs successfully."
    assert result.returncode == 0, (
        f"{FUZZ} did not exit with 0. It exited with {result.returncode}. "
        f"stderr: {result.stderr}"
    )


def write_probe(mode):
    with open("/tmp/worker_probe_mode", "w") as f:
        f.write(mode)
    with open("/tmp/worker_probe.log", "w"):
        pass
    probe = r'''#!/bin/bash
printf '%s\n' "${1-}" >> /tmp/worker_probe.log
mode=$(cat /tmp/worker_probe_mode 2>/dev/null)
case "$mode" in
  hang)
    sleep 10
    ;;
  hang_first)
    count=$(wc -l < /tmp/worker_probe.log)
    if [ "$count" -eq 1 ]; then sleep 10; fi
    ;;
  fail)
    exit 7
    ;;
esac
exit 0
'''
    with open(WORKER, "w") as f:
        f.write(probe)
    os.chmod(WORKER, 0o755)


def read_probe_values():
    with open("/tmp/worker_probe.log") as f:
        return [line.rstrip("\n") for line in f]


def run_checked(path, timeout):
    try:
        start = time.monotonic()
        result = subprocess.run([path], capture_output=True, text=True, timeout=timeout)
        return result, time.monotonic() - start
    except subprocess.TimeoutExpired:
        assert False, f"{path} itself failed to finish within {timeout} seconds."


def test_regression_and_fuzzer_contracts():
    # Substitute an instrumented worker to verify that the test scripts really
    # invoke the required path, pass the required inputs, and enforce timeouts.
    backup = WORKER + ".verifier_backup"
    assert not os.path.exists(backup), f"Unexpected verifier backup path exists: {backup}"
    os.replace(WORKER, backup)
    try:
        write_probe("success")
        result, _ = run_checked(REGRESSION, 8)
        assert result.returncode == 0, "regression.sh must return 0 when the worker succeeds."
        assert read_probe_values() == ["1.0"], (
            "regression.sh must invoke /home/user/worker_fixed.sh exactly once with input 1.0."
        )

        write_probe("hang")
        result, elapsed = run_checked(REGRESSION, 7)
        assert result.returncode == 1, "regression.sh must return 1 when the worker times out."
        assert read_probe_values() == ["1.0"], (
            "regression.sh must run the worker with input 1.0 even in the timeout case."
        )
        assert 1.4 <= elapsed <= 4.5, (
            f"regression.sh did not enforce the required 2-second timeout (elapsed {elapsed:.2f}s)."
        )

        write_probe("fail")
        result, _ = run_checked(REGRESSION, 8)
        assert result.returncode == 1, "regression.sh must return 1 when the worker fails."

        fuzz_runs = []
        for _ in range(2):
            write_probe("success")
            result, _ = run_checked(FUZZ, 20)
            assert result.returncode == 0, "fuzz.sh must return 0 when all worker runs succeed."
            values = read_probe_values()
            assert len(values) == 50, (
                f"fuzz.sh must invoke /home/user/worker_fixed.sh exactly 50 times; got {len(values)}."
            )
            parsed = []
            for raw in values:
                try:
                    value = Decimal(raw)
                except InvalidOperation:
                    assert False, f"fuzz.sh supplied a non-floating-point input: {raw!r}"
                assert value.is_finite() and Decimal("0.0") <= value <= Decimal("10.0"), (
                    f"Fuzz input {raw!r} is outside the required range 0.0 through 10.0."
                )
                parsed.append(value)
            assert len(set(parsed)) > 1, "fuzz.sh must generate varied random inputs."
            fuzz_runs.append(values)
        assert fuzz_runs[0] != fuzz_runs[1], (
            "Two fuzz runs generated the identical sequence; inputs must be randomly generated."
        )

        write_probe("hang_first")
        result, elapsed = run_checked(FUZZ, 8)
        assert result.returncode == 1, "fuzz.sh must return 1 when a worker invocation times out."
        assert len(read_probe_values()) >= 1, "fuzz.sh did not invoke the worker."
        assert 0.65 <= elapsed <= 4.0, (
            f"fuzz.sh did not enforce the required 1-second worker timeout (elapsed {elapsed:.2f}s)."
        )

        write_probe("fail")
        result, _ = run_checked(FUZZ, 8)
        assert result.returncode == 1, "fuzz.sh must return 1 when a worker invocation fails."
    finally:
        try:
            os.unlink(WORKER)
        except FileNotFoundError:
            pass
        os.replace(backup, WORKER)
        for path in ["/tmp/worker_probe_mode", "/tmp/worker_probe.log"]:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
