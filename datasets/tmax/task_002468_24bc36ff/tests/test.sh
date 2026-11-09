#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

INTEGRATE = "/home/user/integrate.sh"
RUN_DIR = "/home/user/simulation_runs"
ALL_INTEGRALS = "/home/user/all_integrals.txt"
BOOTSTRAP = "/home/user/bootstrap.sh"
CI_FILE = "/home/user/ci.txt"
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def trapezoid(path):
    points = []
    with open(path) as f:
        next(f)
        for line in f:
            if line.strip():
                t, e = line.strip().split(',')
                points.append((float(t), float(e)))
    return sum((t2 - t1) * (e1 + e2) / 2.0
               for (t1, e1), (t2, e2) in zip(points, points[1:]))


def run_integrator(path):
    result = subprocess.run([INTEGRATE, path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"integrate.sh failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert NUMBER_RE.fullmatch(output), f"integrate.sh must print only one numerical value, got {result.stdout!r}"
    return float(output)


def test_integrate_script_fixed():
    assert os.path.isfile(INTEGRATE), f"Missing {INTEGRATE}"
    assert os.access(INTEGRATE, os.X_OK), f"{INTEGRATE} is not executable"

    test_file = os.path.join(RUN_DIR, "run_1.csv")
    assert os.path.isfile(test_file), f"Missing {test_file}"
    val = run_integrator(test_file)
    assert 900 < val < 1100, f"integrate.sh output {val} is far from the expected ~1000. Trapezoidal rule might be incorrect."

    fixtures = [
        "time,energy\n0,0\n0.3,1\n1.1,4\n2,2\n",
        "time,energy\n-1,3\n-0.8,-2\n0.7,5\n3.25,1.5\n",
        "time,energy\n0,100\n0.01,0\n2.5,8\n9,3\n10,40\n",
    ]
    for data in fixtures:
        fd, path = tempfile.mkstemp(suffix=".csv")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(data)
            actual = run_integrator(path)
            expected = trapezoid(path)
            assert abs(actual - expected) <= 1e-5 * max(1.0, abs(expected)), \
                f"Incorrect trapezoidal integral for non-uniform input: got {actual}, expected {expected}"
        finally:
            os.unlink(path)


def test_all_integrals_file():
    assert os.path.isfile(ALL_INTEGRALS), f"Missing {ALL_INTEGRALS}"
    with open(ALL_INTEGRALS) as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 50, f"Expected 50 lines in {ALL_INTEGRALS}, found {len(lines)}"

    actual = []
    for i, line in enumerate(lines):
        try:
            val = float(line)
            assert 800 < val < 1200, f"Value {val} on line {i+1} is out of expected range."
            actual.append(val)
        except ValueError:
            pytest.fail(f"Invalid float '{line}' on line {i+1} in {ALL_INTEGRALS}")

    expected = []
    for i in range(1, 51):
        path = os.path.join(RUN_DIR, f"run_{i}.csv")
        assert os.path.isfile(path), f"Missing {path}"
        expected.append(trapezoid(path))

    for got, want in zip(sorted(actual), sorted(expected)):
        assert abs(got - want) <= 0.02, \
            f"{ALL_INTEGRALS} does not contain the 50 trapezoidal integrals; got {got}, expected {want}"


def test_bootstrap_script_exists_and_executable():
    assert os.path.isfile(BOOTSTRAP), f"Missing {BOOTSTRAP}"
    assert os.access(BOOTSTRAP, os.X_OK), f"{BOOTSTRAP} is not executable"


def test_ci_file():
    assert os.path.isfile(CI_FILE), f"Missing {CI_FILE}"
    with open(CI_FILE) as f:
        content = f.read().strip()
    parts = content.split(',')
    assert len(parts) == 2, f"Expected two comma-separated values in {CI_FILE}, got '{content}'"
    try:
        low = float(parts[0])
        high = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse floats from {CI_FILE}: '{content}'")
    assert low < high, f"Lower bound {low} is not less than upper bound {high}"
    assert 900 < low < 1100, f"Lower bound {low} is out of expected range"
    assert 900 < high < 1100, f"Upper bound {high} is out of expected range"


def test_bootstrap_executes_1000_resamples_of_fifty_values():
    with open(ALL_INTEGRALS, "rb") as f:
        original_integrals = f.read()
    with open(CI_FILE, "rb") as f:
        original_ci = f.read()

    sort_path = "/usr/bin/sort"
    real_sort = "/usr/bin/sort.verifier-real"
    log_path = "/tmp/verifier-sort-counts"
    assert os.path.exists(sort_path)
    if os.path.exists(log_path):
        os.unlink(log_path)

    os.rename(sort_path, real_sort)
    wrapper = '''#!/bin/bash
TMP=$(mktemp)
OUT=""
NEED_OUT=0
for ARG in "$@"; do
    if [ "$NEED_OUT" = 1 ]; then OUT="$ARG"; NEED_OUT=0; continue; fi
    case "$ARG" in
        -o) NEED_OUT=1 ;;
        --output=*) OUT=${ARG#--output=} ;;
        -o?*) OUT=${ARG#-o} ;;
    esac
done
/usr/bin/sort.verifier-real "$@" > "$TMP"
RC=$?
if [ -n "$OUT" ] && [ -f "$OUT" ]; then wc -l < "$OUT" >> /tmp/verifier-sort-counts
else wc -l < "$TMP" >> /tmp/verifier-sort-counts
fi
cat "$TMP"
rm -f "$TMP"
exit "$RC"
'''
    try:
        with open(sort_path, "w") as f:
            f.write(wrapper)
        os.chmod(sort_path, 0o755)

        # For 25 zeroes and 25 hundreds, a correct size-50 bootstrap has a
        # binomially distributed mean centered at 50 and a 95% interval near 36..64.
        with open(ALL_INTEGRALS, "w") as f:
            f.write("0\n" * 25 + "100\n" * 25)
        if os.path.exists(CI_FILE):
            os.unlink(CI_FILE)

        result = subprocess.run([BOOTSTRAP], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, f"bootstrap.sh failed: {result.stderr}"
        assert os.path.isfile(CI_FILE), "bootstrap.sh did not write /home/user/ci.txt"

        with open(CI_FILE) as f:
            content = f.read().strip()
        parts = content.split(',')
        assert len(parts) == 2, f"Expected two comma-separated bootstrap bounds, got {content!r}"
        low, high = map(float, parts)
        assert low < 50 < high, f"Bootstrap interval {low},{high} is not centered around the sample mean"
        assert 34 <= low <= 40, f"Bootstrap lower percentile {low} is inconsistent with 50-value resampling"
        assert 60 <= high <= 66, f"Bootstrap upper percentile {high} is inconsistent with 50-value resampling"

        assert os.path.isfile(log_path), "bootstrap.sh did not sort its generated bootstrap means"
        with open(log_path) as f:
            counts = [int(x) for x in f.read().split()]
        assert 1000 in counts, f"bootstrap.sh must generate and sort exactly 1000 means; observed sort sizes {counts}"
    finally:
        if os.path.exists(sort_path):
            os.unlink(sort_path)
        os.rename(real_sort, sort_path)
        with open(ALL_INTEGRALS, "wb") as f:
            f.write(original_integrals)
        with open(CI_FILE, "wb") as f:
            f.write(original_ci)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
