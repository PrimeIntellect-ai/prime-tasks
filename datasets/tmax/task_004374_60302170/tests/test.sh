#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import tempfile

import numpy as np
from scipy import stats as scipy_stats

SCRIPT = '/home/user/benchmark.py'
DATASET = '/home/user/dataset.jsonl'
RESULTS = '/home/user/benchmark_results.json'


def test_benchmark_results():
    assert os.path.isfile(SCRIPT), f"Expected benchmark script {SCRIPT} does not exist."
    assert os.path.isfile(DATASET), f"Expected dataset {DATASET} does not exist."

    # Independently derive the expected valid-record count from the dataset.
    valid_records = []
    with open(DATASET, 'r') as f:
        for line in f:
            record = json.loads(line)
            if isinstance(record.get('text'), str):
                valid_records.append(record)
    expected_count = len(valid_records)
    assert expected_count == 950, f"Expected dataset to contain 950 valid records, found {expected_count}."

    # Load the submitted artifact and directly exercise its schema-filtering logic
    # on independent input containing invalid rows in multiple positions.
    spec = importlib.util.spec_from_file_location('submitted_benchmark', SCRIPT)
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    assert callable(getattr(benchmark, 'load_data', None)), "benchmark.py must provide working load_data logic."

    records = [
        {'id': 1, 'text': 'first'},
        {'id': 2, 'text': None},
        {'id': 3, 'text': 123},
        {'id': 4},
        {'id': 5, 'text': 'last'},
    ]
    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as tmp:
        for record in records:
            tmp.write(json.dumps(record) + '\n')
        temp_path = tmp.name
    try:
        loaded = benchmark.load_data(temp_path)
    finally:
        os.unlink(temp_path)
    assert loaded == [records[0], records[4]], "Invalid records must be skipped without discarding valid records."

    # Run the submitted benchmark. Track the actual samples supplied to scipy's
    # independent t-test so reported statistics can be checked against the run.
    real_ttest_ind = scipy_stats.ttest_ind
    ttest_calls = []

    def tracked_ttest_ind(a, b, *args, **kwargs):
        a_copy = np.asarray(a, dtype=float).copy()
        b_copy = np.asarray(b, dtype=float).copy()
        ttest_calls.append((a_copy, b_copy, args, kwargs))
        return real_ttest_ind(a, b, *args, **kwargs)

    scipy_stats.ttest_ind = tracked_ttest_ind
    try:
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        benchmark.main()
    finally:
        scipy_stats.ttest_ind = real_ttest_ind

    assert os.path.isfile(RESULTS), f"Expected results file {RESULTS} does not exist. Did you run the script?"
    with open(RESULTS, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULTS} is not valid JSON."

    # Preserve the original final-state assertions.
    assert "error" not in results, f"Results still contain an error: {results.get('error')}. The bug was not fixed properly."
    valid_count = results.get("valid_records_count")
    assert valid_count == 950, f"Expected valid_records_count to be 950, but got {valid_count}."

    p_value = results.get("p_value")
    assert isinstance(p_value, float), f"Expected p_value to be a float, but got {type(p_value)}."
    method_A_mean = results.get("method_A_mean_time")
    assert isinstance(method_A_mean, float), f"Expected method_A_mean_time to be a float, but got {type(method_A_mean)}."
    method_B_mean = results.get("method_B_mean_time")
    assert isinstance(method_B_mean, float), f"Expected method_B_mean_time to be a float, but got {type(method_B_mean)}."

    assert valid_count == expected_count
    assert ttest_calls, "benchmark.py did not perform scipy's independent t-test."
    matching_calls = [c for c in ttest_calls if len(c[0]) == expected_count and len(c[1]) == expected_count]
    assert matching_calls, "The t-test must use one timing sample per valid record for both methods."
    times_a, times_b, args, kwargs = matching_calls[-1]

    assert np.all(np.isfinite(times_a)) and np.all(times_a >= 0), "Method A timings are invalid."
    assert np.all(np.isfinite(times_b)) and np.all(times_b >= 0), "Method B timings are invalid."
    expected_a_mean = float(np.mean(times_a))
    expected_b_mean = float(np.mean(times_b))
    expected_p = float(real_ttest_ind(times_a, times_b, *args, **kwargs).pvalue)

    assert math.isfinite(method_A_mean) and method_A_mean > 0
    assert math.isfinite(method_B_mean) and method_B_mean > 0
    assert method_B_mean < method_A_mean, "The simulated batch method should benchmark faster than the sequential method."
    assert math.isfinite(p_value) and 0.0 <= p_value <= 1.0
    assert math.isclose(method_A_mean, expected_a_mean, rel_tol=1e-9, abs_tol=1e-15), "Reported Method A mean does not match measured timings."
    assert math.isclose(method_B_mean, expected_b_mean, rel_tol=1e-9, abs_tol=1e-15), "Reported Method B mean does not match measured timings."
    assert math.isclose(p_value, expected_p, rel_tol=1e-9, abs_tol=1e-300), "Reported p-value does not match the independent t-test."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
