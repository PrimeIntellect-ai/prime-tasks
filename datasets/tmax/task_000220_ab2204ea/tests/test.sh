#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import re
import shutil
import stat
import subprocess

SCRIPT = '/home/user/profiler.sh'
RESULTS = '/home/user/profile_results.txt'
SIMULATOR = '/home/user/spectroscopy_sim.py'


def test_profiler_script_exists_and_executable():
    """Verify that /home/user/profiler.sh exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_profiler_script_no_python_for_bootstrap():
    """Verify that the script does not use perl for the bootstrap logic."""
    with open(SCRIPT, 'r') as f:
        content = f.read()
    assert 'perl' not in content.lower(), "Perl should not be used in the script."


def test_profile_results_exist():
    """Verify that /home/user/profile_results.txt exists."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist."


def test_profile_results_format_and_values():
    """Verify the initially requested N=50, B=5000 result."""
    with open(RESULTS, 'r') as f:
        content = f.read().strip()

    pattern = r'^N=50,\s*B=5000,\s*CI=\[\s*([\d\.]+)\s*,\s*([\d\.]+)\s*\]$'
    match = re.match(pattern, content)
    assert match, (f"Content '{content}' does not match the expected format "
                   "'N=50, B=5000, CI=[<lower>, <upper>]'.")

    lower_bound = float(match.group(1))
    upper_bound = float(match.group(2))
    assert 154.0 <= lower_bound <= 158.0, (
        f"Lower bound {lower_bound} is outside the expected range [154.0, 158.0].")
    assert 174.0 <= upper_bound <= 178.5, (
        f"Upper bound {upper_bound} is outside the expected range [174.0, 178.5].")


def parse_result(expected_n, expected_b):
    with open(RESULTS, 'r') as f:
        text = f.read().strip()
    pattern = (rf'^N={expected_n},\s*B={expected_b},\s*CI=\['
               rf'\s*(-?\d+\.\d{{2}})\s*,\s*(-?\d+\.\d{{2}})\s*\]$')
    match = re.fullmatch(pattern, text)
    assert match, f"Unexpected profiler output: {text!r}"
    return float(match.group(1)), float(match.group(2))


def acceptable_quantile_ranges(values):
    # Exact distribution of means of every possible with-replacement resample.
    means = sorted(sum(sample) / len(values)
                   for sample in itertools.product(values, repeat=len(values)))
    last = len(means) - 1
    # These probability bands allow ordinary Monte Carlo variation while still
    # requiring the reported bounds to behave like 2.5% and 97.5% quantiles.
    lower_range = (means[int(0.005 * last)], means[int(0.055 * last)])
    upper_range = (means[int(0.945 * last)], means[int(0.995 * last)])
    return lower_range, upper_range


def test_profiler_executes_simulator_and_bootstraps_collected_data():
    original_sim = open(SIMULATOR, 'rb').read()
    original_mode = stat.S_IMODE(os.stat(SIMULATOR).st_mode)
    result_existed = os.path.exists(RESULTS)
    original_result = open(RESULTS, 'rb').read() if result_existed else None
    data_path = '/tmp/verifier_spectroscopy_values.txt'
    log_path = '/tmp/verifier_spectroscopy_calls.txt'

    wrapper = '''#!/usr/bin/env python3
import argparse
p = argparse.ArgumentParser()
p.add_argument("--seed", type=int, required=True)
a = p.parse_args()
with open("/tmp/verifier_spectroscopy_calls.txt", "a") as f:
    f.write(str(a.seed) + "\\n")
with open("/tmp/verifier_spectroscopy_values.txt") as f:
    values = [float(x.strip()) for x in f if x.strip()]
if not 1 <= a.seed <= len(values):
    raise SystemExit(3)
print(f"Time: {values[a.seed - 1]:.2f} ms")
'''

    try:
        with open(SIMULATOR, 'w') as f:
            f.write(wrapper)
        os.chmod(SIMULATOR, 0o755)

        # "Exactly two arguments" requires both missing and extra arguments to fail.
        for args in (['4'], ['4', '20', 'extra']):
            proc = subprocess.run([SCRIPT] + args, cwd='/home/user',
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, timeout=30)
            assert proc.returncode != 0, f"profiler accepted invalid arguments: {args}"

        datasets = [
            [10.0, 20.0, 30.0, 40.0],
            [101.0, 107.0, 150.0, 260.0],
        ]
        n, b = 4, 1200
        observed = []
        for values in datasets:
            with open(data_path, 'w') as f:
                f.write('\n'.join(map(str, values)) + '\n')
            open(log_path, 'w').close()

            proc = subprocess.run([SCRIPT, str(n), str(b)], cwd='/home/user',
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, timeout=90)
            assert proc.returncode == 0, (
                f"profiler execution failed: stdout={proc.stdout!r}, stderr={proc.stderr!r}")

            with open(log_path) as f:
                calls = [int(line.strip()) for line in f if line.strip()]
            assert calls == list(range(1, n + 1)), (
                f"simulator seeds must be exactly 1 through N; observed {calls}")

            lower, upper = parse_result(n, b)
            lower_range, upper_range = acceptable_quantile_ranges(values)
            assert lower_range[0] - 0.01 <= lower <= lower_range[1] + 0.01, (
                f"lower bound {lower} is not a plausible bootstrap percentile for {values}")
            assert upper_range[0] - 0.01 <= upper <= upper_range[1] + 0.01, (
                f"upper bound {upper} is not a plausible bootstrap percentile for {values}")
            assert lower <= upper
            observed.append((lower, upper))

        assert observed[0] != observed[1], "CI did not respond to changed simulator output"
    finally:
        with open(SIMULATOR, 'wb') as f:
            f.write(original_sim)
        os.chmod(SIMULATOR, original_mode)
        if result_existed:
            with open(RESULTS, 'wb') as f:
                f.write(original_result)
        elif os.path.exists(RESULTS):
            os.remove(RESULTS)
        for path in (data_path, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
