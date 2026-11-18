#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess

import numpy as np

COMPUTE = "/home/user/compute.py"
OPTIMIZE = "/home/user/optimize.sh"
BEST = "/home/user/best_fc.txt"
SIGNAL = "/home/user/signal.csv"


def run(cmd, timeout=120):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)


def reference_sigma(values, fc):
    values = np.asarray(values, dtype=float)
    coeff = np.fft.fft(values)
    freqs = np.fft.fftfreq(values.size, d=0.01)
    coeff[np.abs(freqs) > fc] = 0
    filtered = np.fft.ifft(coeff).real
    hankel = np.lib.stride_tricks.sliding_window_view(filtered, 50)
    return float(np.linalg.svd(hankel, compute_uv=False)[0])


def assert_compute_matches(values, fc, tmp_path):
    csv_path = tmp_path / f"signal_fc_{fc}.csv"
    np.savetxt(csv_path, values, fmt="%.12g")
    result = run(["python3", COMPUTE, str(csv_path), str(fc)])
    assert result.returncode == 0, result.stderr

    output = result.stdout.strip()
    float_pattern = r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
    assert re.fullmatch(float_pattern, output), (
        "compute.py must print only one floating-point value; "
        f"stdout was {result.stdout!r}"
    )
    actual = float(output)
    assert np.isfinite(actual)
    expected = reference_sigma(values, fc)
    assert np.isclose(actual, expected, rtol=1e-7, atol=1e-7), (
        f"For fc={fc}, expected dominant singular value {expected}, got {actual}"
    )


def test_best_fc_exists_and_correct():
    assert os.path.isfile(BEST), f"File {BEST} is missing. Did the bash script run successfully?"
    with open(BEST) as f:
        content = f.read().strip()
    assert content == "6", f"Expected the best cutoff frequency to be '6', but got '{content}'."


def test_scripts_exist():
    assert os.path.isfile(COMPUTE), f"Python script {COMPUTE} is missing."
    assert os.path.isfile(OPTIMIZE), f"Bash script {OPTIMIZE} is missing."


def test_compute_performs_required_fft_hankel_and_svd(tmp_path):
    n = 500
    t = np.arange(n) * 0.01
    values1 = (
        1.7
        + 2.3 * np.sin(2 * np.pi * 3 * t)
        - 1.1 * np.cos(2 * np.pi * 9 * t)
        + 4.2 * np.sin(2 * np.pi * 27 * t)
    )
    assert_compute_matches(values1, 7, tmp_path)

    rng = np.random.default_rng(7319)
    values2 = (
        0.4 * rng.normal(size=n)
        + 1.8 * np.cos(2 * np.pi * 5 * t)
        + 0.9 * np.sin(2 * np.pi * 14 * t)
        + 2.6 * np.cos(2 * np.pi * 33 * t)
    )
    assert_compute_matches(values2, 14, tmp_path)


def test_required_pipeline_was_executable_and_produces_recorded_answer():
    result = run(["bash", OPTIMIZE, "85.0"], timeout=180)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(BEST), f"{OPTIMIZE} did not create {BEST}"
    with open(BEST) as f:
        content = f.read().strip()
    assert content == "6", f"Expected the best cutoff frequency to be '6', but got '{content}'."


def test_bash_optimizer_searches_all_cutoffs_and_uses_compute():
    call_log = "/tmp/compute_calls_verifier"
    with open(COMPUTE, "rb") as f:
        original_compute = f.read()
    original_mode = stat.S_IMODE(os.stat(COMPUTE).st_mode)
    best_existed = os.path.exists(BEST)
    original_best = None
    if best_existed:
        with open(BEST, "rb") as f:
            original_best = f.read()

    stub = '''#!/usr/bin/env python3
import sys
with open("/tmp/compute_calls_verifier", "a") as log:
    log.write("\\t".join(sys.argv[1:]) + "\\n")
fc = int(sys.argv[-1])
print(10.0 + (fc - 13) ** 2)
'''

    try:
        if os.path.exists(call_log):
            os.remove(call_log)
        with open(COMPUTE, "w") as f:
            f.write(stub)
        os.chmod(COMPUTE, 0o755)

        result = run(["bash", OPTIMIZE, "10.0"])
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(call_log), "optimize.sh did not invoke compute.py"

        with open(call_log) as f:
            calls = [line.rstrip("\n").split("\t") for line in f if line.strip()]
        assert all(len(args) == 2 for args in calls), (
            "Each compute.py invocation must receive the input CSV and cutoff frequency"
        )
        cutoffs = [int(args[-1]) for args in calls]
        assert set(cutoffs) == set(range(1, 21)), (
            f"optimize.sh must search every integer cutoff from 1 through 20; got {cutoffs}"
        )
        assert all(args[0].endswith("signal.csv") for args in calls), (
            "optimize.sh must pass signal.csv to compute.py"
        )

        assert os.path.isfile(BEST), f"{OPTIMIZE} did not write {BEST}"
        with open(BEST) as f:
            answer = f.read().strip()
        assert answer == "13", (
            "For the controlled compute.py results and target 10.0, "
            f"the optimizer should select 13, but wrote {answer!r}"
        )
    finally:
        with open(COMPUTE, "wb") as f:
            f.write(original_compute)
        os.chmod(COMPUTE, original_mode)
        if best_existed:
            with open(BEST, "wb") as f:
                f.write(original_best)
        elif os.path.exists(BEST):
            os.remove(BEST)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
