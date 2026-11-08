#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import re
import stat
import subprocess

import numpy as np
from scipy.optimize import minimize
from scipy.stats import t as student_t
from scipy.stats import ttest_ind

EXPECTED_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <time.h>

int main(int argc, char *argv[]) {
    double x = 0.0, y = 0.0;
    int opt;
    while ((opt = getopt(argc, argv, "x:y:")) != -1) {
        switch (opt) {
            case 'x': x = atof(optarg); break;
            case 'y': y = atof(optarg); break;
        }
    }

    // Seed random number generator
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    srand(ts.tv_nsec ^ (getpid() << 16));

    // True optimal is x=7.5, y=3.2
    double base_time = pow(x - 7.5, 2) + pow(y - 3.2, 2) + 5.0;

    // Add small noise to enable variance for the t-test
    double noise = ((double)rand() / RAND_MAX) * 0.5 - 0.25;
    double actual_time = base_time + noise;

    if (actual_time < 0.1) actual_time = 0.1;

    printf("Runtime: %.4f\n", actual_time);
    return 0;
}
'''

SOURCE = '/home/user/simulator.c'
SIMULATOR = '/home/user/simulator'
REPORT = '/home/user/report.json'


def run_simulator(x, y):
    proc = subprocess.run(
        [SIMULATOR, '-x', str(x), '-y', str(y)],
        text=True, capture_output=True, timeout=5, check=True
    )
    lines = proc.stdout.strip().splitlines()
    assert len(lines) == 1, f"Simulator must emit one output line, got: {proc.stdout!r}"
    match = re.fullmatch(r'Runtime:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)', lines[0])
    assert match, f"Unexpected simulator output: {lines[0]!r}"
    value = float(match.group(1))
    assert math.isfinite(value), "Simulator returned a non-finite runtime"
    return value


def test_complete_submission():
    # Keep the original executable checks and additionally establish that this is
    # a GCC-produced native artifact implementing the supplied source.
    assert os.path.isfile(SIMULATOR), f"{SIMULATOR} does not exist. Did you compile the simulator?"
    st = os.stat(SIMULATOR)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SIMULATOR} is not executable."
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing"
    with open(SOURCE, 'r') as f:
        assert f.read() == EXPECTED_SOURCE, "The supplied simulator source was modified"
    with open(SIMULATOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "simulator must be a compiled ELF executable"
    comment = subprocess.run(
        ['readelf', '-p', '.comment', SIMULATOR], text=True,
        capture_output=True, timeout=5, check=True
    ).stdout
    assert 'GCC:' in comment, "simulator is not a GCC-produced executable"
    assert os.path.getmtime(SIMULATOR) >= os.path.getmtime(SOURCE), "simulator predates the supplied source"

    # Exercise hidden, non-optimal parameter values. Their expected means are
    # derived from the supplied simulator model rather than from the report.
    probe_points = [(-3.4, 6.7), (1.25, -4.5), (4.4, 9.1), (10.8, 0.6), (13.2, 7.7)]
    for x, y in probe_points:
        observed = np.mean([run_simulator(x, y) for _ in range(12)])
        expected = (x - 7.5) ** 2 + (y - 3.2) ** 2 + 5.0
        assert abs(observed - expected) < 0.25, (
            f"Compiled simulator behavior is wrong at x={x}, y={y}: "
            f"mean {observed}, expected approximately {expected}"
        )

    # The instruction requires a Python optimization/statistics script. Locate
    # and actually run that artifact, requiring it to regenerate the report.
    candidates = []
    for path in sorted(glob.glob('/home/user/**/*.py', recursive=True)):
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, 'r').read()
        except (OSError, UnicodeDecodeError):
            continue
        if 'minimize' in text and 'Nelder-Mead' in text and 'ttest_ind' in text:
            candidates.append(path)
    assert candidates, "No Python script using minimize/Nelder-Mead and ttest_ind was found"
    if os.path.exists(REPORT):
        os.remove(REPORT)
    proc = subprocess.run(
        ['python3', candidates[0]], cwd='/home/user', text=True,
        capture_output=True, timeout=180
    )
    assert proc.returncode == 0, (
        f"Optimization script failed with exit code {proc.returncode}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )

    # Recheck the executable after running untrusted script code.
    assert os.path.isfile(SIMULATOR)
    assert os.access(SIMULATOR, os.X_OK)
    with open(SIMULATOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF'

    # Keep all original report shape and type assertions.
    assert os.path.isfile(REPORT), f"{REPORT} does not exist."
    try:
        with open(REPORT, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        assert False, f"{REPORT} is not a valid JSON file."

    expected_keys = {'optimal_x', 'optimal_y', 'p_value', 't_statistic'}
    assert set(report.keys()) == expected_keys, f"report.json must contain exactly the keys: {expected_keys}"
    assert isinstance(report['optimal_x'], (int, float)), "optimal_x must be a number"
    assert isinstance(report['optimal_y'], (int, float)), "optimal_y must be a number"
    assert isinstance(report['p_value'], (int, float)), "p_value must be a number"
    assert isinstance(report['t_statistic'], (int, float)), "t_statistic must be a number"
    assert all(math.isfinite(float(report[k])) for k in expected_keys), "Report values must be finite"

    # Recompute the optimum from fresh simulator samples. Fit a quadratic runtime
    # surface to sampled observations, then optimize that sampled model with the
    # required Nelder-Mead method from [0, 0].
    rows, values = [], []
    for x in (-2.0, 1.0, 4.0, 8.0, 12.0):
        for y in (-3.0, 0.0, 3.0, 6.0, 9.0):
            mean_runtime = np.mean([run_simulator(x, y) for _ in range(6)])
            rows.append([x*x, y*y, x*y, x, y, 1.0])
            values.append(mean_runtime)
    coefficients, *_ = np.linalg.lstsq(np.asarray(rows), np.asarray(values), rcond=None)

    def sampled_model(z):
        x, y = z
        return float(np.dot(coefficients, [x*x, y*y, x*y, x, y, 1.0]))

    recomputed = minimize(
        sampled_model, np.array([0.0, 0.0]), method='Nelder-Mead',
        options={'xatol': 1e-9, 'fatol': 1e-9, 'maxiter': 3000}
    )
    assert recomputed.success, f"Verifier optimization failed: {recomputed.message}"
    expected_x = round(float(recomputed.x[0]), 1)
    expected_y = round(float(recomputed.x[1]), 1)

    # Preserve the original known-optimum assertions and tie them to the fresh
    # optimization result.
    assert abs(report['optimal_x'] - 7.5) < 1e-5, f"Expected optimal_x to be 7.5, got {report['optimal_x']}"
    assert abs(report['optimal_y'] - 3.2) < 1e-5, f"Expected optimal_y to be 3.2, got {report['optimal_y']}"
    assert report['optimal_x'] == expected_x, f"Reported x does not match sampled optimum {expected_x}"
    assert report['optimal_y'] == expected_y, f"Reported y does not match sampled optimum {expected_y}"
    assert round(float(report['optimal_x']), 1) == float(report['optimal_x'])
    assert round(float(report['optimal_y']), 1) == float(report['optimal_y'])

    # Independently collect the required 20+20 samples and recompute Welch's
    # t-test. Compare the reported statistic to this fresh result and verify that
    # its p-value is mathematically possible for a 20-vs-20 Welch test.
    baseline = [run_simulator(0.0, 0.0) for _ in range(20)]
    optimized = [run_simulator(report['optimal_x'], report['optimal_y']) for _ in range(20)]
    fresh_t, fresh_p = ttest_ind(baseline, optimized, equal_var=False)
    assert math.isfinite(float(fresh_t)) and math.isfinite(float(fresh_p))
    assert fresh_t > 10.0 and fresh_p < 0.01, "Fresh samples do not show the required improvement"

    reported_t = float(report['t_statistic'])
    reported_p = float(report['p_value'])
    assert reported_t > 10.0, f"Expected a large positive t_statistic (> 10), got {reported_t}"
    assert reported_p < 0.01, f"Expected a very small p_value (< 0.01), got {reported_p}"
    assert reported_p > 0.0, "p_value must be a computed positive probability, not zero"
    assert 0.5 * fresh_t <= reported_t <= 2.0 * fresh_t, (
        f"Reported t-statistic {reported_t} is inconsistent with fresh simulator samples ({fresh_t})"
    )

    # For two groups of 20, Welch-Satterthwaite degrees of freedom must be in
    # [19, 38]. Thus a genuine two-sided scipy p-value for the reported t must
    # fall between these two derived endpoint probabilities.
    endpoint_p = [2.0 * student_t.sf(abs(reported_t), df) for df in (19.0, 38.0)]
    lower, upper = min(endpoint_p), max(endpoint_p)
    assert lower <= reported_p <= upper, (
        f"Reported p-value {reported_p} is not consistent with a Welch t-test "
        f"having t={reported_t} and 20 samples per group"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
