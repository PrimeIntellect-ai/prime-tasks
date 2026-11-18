#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_H5DUMP="$(command -v h5dump)"
SAVED_H5DUMP="/tmp/h5dump.real.$$"
H5DUMP_LOG="/tmp/h5dump_calls.log"

mv "$REAL_H5DUMP" "$SAVED_H5DUMP"
cat > "$REAL_H5DUMP" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$H5DUMP_LOG"
exec "$SAVED_H5DUMP" "\$@"
EOF
chmod 755 "$REAL_H5DUMP"

cleanup() {
    rm -f "$REAL_H5DUMP"
    mv "$SAVED_H5DUMP" "$REAL_H5DUMP"
    rm -f "$H5DUMP_LOG"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import h5py
import numpy as np
import pytest

SCRIPT = "/home/user/analyze_seq.sh"
RESULTS = "/home/user/regression_results.txt"
TEST_LOG = "/home/user/test_log.txt"
BASELINE = "/home/user/data/baseline.txt"
H5DUMP_LOG = "/tmp/h5dump_calls.log"
ORIGINAL_H5 = "/home/user/data/seq_stats.h5"
ORIGINAL_EXPECTED = "Slope: 0.50\nIntercept: 35.00"


def run_script(input_path):
    for path in (RESULTS, TEST_LOG, H5DUMP_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [SCRIPT, input_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Script exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(H5DUMP_LOG), "The executed script did not invoke h5dump."
    assert os.path.getsize(H5DUMP_LOG) > 0, "The executed script did not invoke h5dump."


def read_required(path):
    assert os.path.isfile(path), f"Output file {path} does not exist."
    with open(path, "r") as f:
        return f.read()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_script_no_forbidden_tools():
    if not os.path.isfile(SCRIPT):
        pytest.skip(f"Script {SCRIPT} does not exist.")

    with open(SCRIPT, "r") as f:
        content = f.read()

    forbidden = ["python", "perl", "Rscript"]
    for tool in forbidden:
        assert tool not in content, (
            f"Forbidden tool '{tool}' found in {SCRIPT}. "
            "You must use standard CLI tools."
        )


def test_execute_on_original_input():
    with open(BASELINE, "w") as f:
        f.write(ORIGINAL_EXPECTED + "\n")
    run_script(ORIGINAL_H5)


def test_regression_results():
    content = read_required(RESULTS).strip()
    assert content == ORIGINAL_EXPECTED, (
        f"Contents of {RESULTS} do not match expected results. Got:\n{content}"
    )


def test_test_log():
    content = read_required(TEST_LOG).strip()
    assert content == "PASS", (
        f"Contents of {TEST_LOG} are incorrect. Expected 'PASS', got '{content}'."
    )


def test_dynamic_input_and_baseline_comparison():
    rng = secrets.SystemRandom()

    while True:
        xs = sorted(rng.sample(range(3, 180), 7))
        ys = [rng.randint(11, 93) + rng.randint(0, 9) / 10.0 for _ in xs]
        n = len(xs)
        sx = sum(xs)
        sy = sum(ys)
        sxy = sum(x * y for x, y in zip(xs, ys))
        sx2 = sum(x * x for x in xs)
        slope = (n * sxy - sx * sy) / (n * sx2 - sx * sx)
        intercept = (sy - slope * sx) / n

        # Avoid formatting edge cases exactly on a half-cent boundary.
        def safely_roundable(value):
            scaled = abs(value) * 100
            return abs((scaled - math.floor(scaled)) - 0.5) > 1e-5

        if abs(slope) > 0.1 and abs(intercept) > 0.1 and safely_roundable(slope) and safely_roundable(intercept):
            break

    challenge_h5 = f"/tmp/verifier_seq_{secrets.token_hex(8)}.h5"
    expected = f"Slope: {slope:.2f}\nIntercept: {intercept:.2f}\n"

    try:
        with h5py.File(challenge_h5, "w") as h5:
            h5.create_dataset("Position", data=np.asarray(xs, dtype=np.int64))
            h5.create_dataset("GC_content", data=np.asarray(ys, dtype=np.float64))

        # A deliberately wrong baseline verifies that results are computed from
        # the HDF5 data rather than copied from the exposed baseline.
        with open(BASELINE, "w") as f:
            f.write("Slope: 99999.99\nIntercept: -99999.99\n")
        run_script(challenge_h5)
        assert read_required(RESULTS) == expected, (
            "Regression output was not correctly derived from the supplied HDF5 datasets."
        )
        assert read_required(TEST_LOG).strip() == "FAIL", (
            "The script must write FAIL when computed results differ from the baseline."
        )

        # The same computed result must pass once the exact baseline is supplied.
        with open(BASELINE, "w") as f:
            f.write(expected)
        run_script(challenge_h5)
        assert read_required(RESULTS) == expected, (
            "Regression output changed or was not recomputed on the supplied HDF5 input."
        )
        assert read_required(TEST_LOG).strip() == "PASS", (
            "The script must write PASS when computed results exactly match the baseline."
        )
    finally:
        try:
            os.remove(challenge_h5)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
