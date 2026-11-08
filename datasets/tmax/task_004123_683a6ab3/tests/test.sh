#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import numbers
import os
import runpy
import subprocess
import sys
import time
import timeit
from collections import Counter

import numpy as np
import pandas as pd
import pytest
from scipy import stats

HOME = '/home/user'
PIPELINE = f'{HOME}/pipeline.py'
BENCHMARK = f'{HOME}/benchmark.py'
PROCESSED = f'{HOME}/processed.csv'
REPORT = f'{HOME}/report.json'


def run_script(path, timeout=120):
    result = subprocess.run(
        [sys.executable, path], capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f'{path} failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def expected_processed():
    data = pd.read_csv(f'{HOME}/data.csv')
    meta = pd.read_csv(f'{HOME}/meta.csv')
    expected = data.merge(meta, on='doc_id', how='left')
    expected['category_id'] = expected['category_id'].fillna(-1).astype(np.int64)
    return expected


def cosine_top_five(frame, query_id):
    ids = frame['doc_id'].to_numpy(dtype=np.int64)
    features = frame[['f1', 'f2', 'f3', 'f4', 'f5']].to_numpy(dtype=float)
    matches = np.flatnonzero(ids == query_id)
    assert len(matches) == 1
    query_index = int(matches[0])
    norms = np.linalg.norm(features, axis=1)
    query_norm = norms[query_index]
    assert query_norm > 0
    similarities = features.dot(features[query_index]) / (norms * query_norm)
    similarities[query_index] = -np.inf
    order = np.lexsort((ids, -similarities))
    return [int(x) for x in ids[order[:5]]]


def load_report():
    assert os.path.isfile(REPORT), f'File missing: {REPORT}'
    with open(REPORT, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'File {REPORT} is not valid JSON: {exc}')


def test_pipeline_and_processed_csv():
    assert os.path.isfile(PIPELINE), f'File missing: {PIPELINE}'
    run_script(PIPELINE)
    assert os.path.isfile(PROCESSED), f'File missing: {PROCESSED}'

    actual = pd.read_csv(PROCESSED)
    expected = expected_processed()

    assert list(actual.columns) == list(expected.columns)
    assert actual.shape == expected.shape == (1000, 7)
    assert actual['doc_id'].tolist() == list(range(1, 1001))
    assert actual['doc_id'].dtype == np.dtype('int64')
    assert actual['category_id'].dtype == np.dtype('int64'), (
        f"category_id must be numpy int64, got {actual['category_id'].dtype}"
    )
    assert actual['category_id'].tolist() == expected['category_id'].tolist()
    np.testing.assert_allclose(
        actual[['f1', 'f2', 'f3', 'f4', 'f5']].to_numpy(),
        expected[['f1', 'f2', 'f3', 'f4', 'f5']].to_numpy(),
        rtol=0,
        atol=1e-14,
    )

    # Preserve the original row-level assertions.
    with open(PROCESSED, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    assert len(rows) == 1000
    for row in rows:
        doc_id = int(row['doc_id'])
        category_id = row['category_id']
        assert category_id.strip() != '', f'Empty category_id found for doc_id {doc_id}'
        assert 'nan' not in category_id.lower(), f'NaN category_id found for doc_id {doc_id}'
        if 501 <= doc_id <= 600:
            assert category_id == '-1', (
                f"Expected category_id '-1' for missing doc_id {doc_id}, got '{category_id}'"
            )


def test_benchmark_and_report_on_real_data():
    assert os.path.isfile(BENCHMARK), f'File missing: {BENCHMARK}'
    run_script(BENCHMARK)
    report = load_report()
    frame = pd.read_csv(PROCESSED)

    required = {
        'top_5_for_10', 'mean_time_sec', 'ci_lower', 'ci_upper',
        'category_id_dtype'
    }
    assert set(report) == required, f'report.json must have exactly these keys: {sorted(required)}'

    # Preserve the original expected-result assertion and independently derive it.
    expected_top_5 = [999, 584, 829, 693, 22]
    assert report['top_5_for_10'] == expected_top_5, (
        f"Expected top_5_for_10 to be {expected_top_5}, got {report['top_5_for_10']}"
    )
    assert report['top_5_for_10'] == cosine_top_five(frame, 10)
    assert all(type(x) is int for x in report['top_5_for_10'])

    assert report['category_id_dtype'] == 'int64', (
        f"Expected category_id_dtype to be 'int64', got {report['category_id_dtype']}"
    )
    assert str(frame['category_id'].dtype) == report['category_id_dtype']

    for key in ['mean_time_sec', 'ci_lower', 'ci_upper']:
        assert key in report, f"Key '{key}' missing in report.json"
        assert isinstance(report[key], (int, float)) and not isinstance(report[key], bool)
        assert math.isfinite(report[key]), f"Key '{key}' must be finite"

    mean_time = report['mean_time_sec']
    ci_lower = report['ci_lower']
    ci_upper = report['ci_upper']
    assert mean_time > 0, f'mean_time_sec must be greater than 0, got {mean_time}'
    assert ci_lower < mean_time, f'ci_lower ({ci_lower}) must be less than mean ({mean_time})'
    assert mean_time < ci_upper, f'mean ({mean_time}) must be less than ci_upper ({ci_upper})'


def test_benchmark_is_executed_and_times_all_queries_with_student_t_ci():
    # Replace processed.csv temporarily with a deterministic challenge dataset.
    # This prevents a hardcoded Top-5 answer from passing.
    rng = np.random.default_rng(73191)
    features = rng.normal(size=(1000, 5))
    features[9] = np.array([1.0, 0.0, 0.0, 0.0, 0.0])
    features[1] = features[9]
    features[2] = features[9]
    features[3] = features[9]
    challenge = pd.DataFrame(features, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
    challenge.insert(0, 'doc_id', np.arange(1, 1001, dtype=np.int64))
    challenge['category_id'] = np.arange(1000, dtype=np.int64) % 9 + 1
    expected_top = cosine_top_five(challenge, 10)

    with open(PROCESSED, 'rb') as f:
        saved_processed = f.read()
    saved_report = None
    if os.path.exists(REPORT):
        with open(REPORT, 'rb') as f:
            saved_report = f.read()

    durations = [0.001 + ((i % 11) - 5) * 0.00008 for i in range(1000)]
    timer_state = {'calls': 0, 'value': 1000.0, 'loop_values': set()}
    function_calls = Counter()
    original_profile = sys.getprofile()
    original_time = time.time
    original_perf = time.perf_counter
    original_process = time.process_time
    original_monotonic = time.monotonic
    original_time_ns = getattr(time, 'time_ns', None)
    original_perf_ns = getattr(time, 'perf_counter_ns', None)
    original_process_ns = getattr(time, 'process_time_ns', None)
    original_monotonic_ns = getattr(time, 'monotonic_ns', None)
    original_default_timer = timeit.default_timer

    def record_loop_values(frame):
        for value in frame.f_locals.values():
            if isinstance(value, numbers.Integral):
                ivalue = int(value)
                if 0 <= ivalue <= 1000:
                    timer_state['loop_values'].add(ivalue)
            elif isinstance(value, pd.Series) and 'doc_id' in value.index:
                try:
                    timer_state['loop_values'].add(int(value['doc_id']))
                except Exception:
                    pass

    def fake_seconds():
        frame = sys._getframe(1)
        if os.path.abspath(frame.f_code.co_filename) != os.path.abspath(BENCHMARK):
            return original_perf()
        record_loop_values(frame)
        call = timer_state['calls']
        pair = call // 2
        if call % 2 == 0:
            result = timer_state['value']
        else:
            if pair >= len(durations):
                # Extra benchmark timer calls are deliberately visible.
                timer_state['value'] += 0.01
            else:
                timer_state['value'] += durations[pair]
            result = timer_state['value']
        timer_state['calls'] += 1
        return result

    def fake_ns():
        return int(round(fake_seconds() * 1_000_000_000))

    def profiler(frame, event, arg):
        if event == 'call' and os.path.abspath(frame.f_code.co_filename) == os.path.abspath(BENCHMARK):
            function_calls[frame.f_code.co_name] += 1
        return profiler

    generated_report = None
    execution_error = None
    try:
        challenge.to_csv(PROCESSED, index=False)
        if os.path.exists(REPORT):
            os.remove(REPORT)

        time.time = fake_seconds
        time.perf_counter = fake_seconds
        time.process_time = fake_seconds
        time.monotonic = fake_seconds
        if original_time_ns is not None:
            time.time_ns = fake_ns
        if original_perf_ns is not None:
            time.perf_counter_ns = fake_ns
        if original_process_ns is not None:
            time.process_time_ns = fake_ns
        if original_monotonic_ns is not None:
            time.monotonic_ns = fake_ns
        timeit.default_timer = fake_seconds
        sys.setprofile(profiler)

        try:
            runpy.run_path(BENCHMARK, run_name='__main__')
        except SystemExit as exc:
            if exc.code not in (None, 0):
                raise
        finally:
            sys.setprofile(original_profile)

        generated_report = load_report()
    except BaseException as exc:
        execution_error = exc
    finally:
        sys.setprofile(original_profile)
        time.time = original_time
        time.perf_counter = original_perf
        time.process_time = original_process
        time.monotonic = original_monotonic
        if original_time_ns is not None:
            time.time_ns = original_time_ns
        if original_perf_ns is not None:
            time.perf_counter_ns = original_perf_ns
        if original_process_ns is not None:
            time.process_time_ns = original_process_ns
        if original_monotonic_ns is not None:
            time.monotonic_ns = original_monotonic_ns
        timeit.default_timer = original_default_timer

        with open(PROCESSED, 'wb') as f:
            f.write(saved_processed)
        if saved_report is not None:
            with open(REPORT, 'wb') as f:
                f.write(saved_report)
        elif os.path.exists(REPORT):
            os.remove(REPORT)

    if execution_error is not None:
        raise execution_error

    assert generated_report['top_5_for_10'] == expected_top, (
        'benchmark.py did not compute cosine Top-5 from the supplied processed.csv'
    )
    assert timer_state['calls'] == 2000, (
        f"Expected exactly one start/end timing pair for each of 1000 queries; "
        f"observed {timer_state['calls']} timer calls"
    )
    assert any(count >= 1000 for count in function_calls.values()), (
        'No benchmark-defined search function was invoked for all 1000 queries'
    )
    seen = timer_state['loop_values']
    assert set(range(1, 1001)).issubset(seen) or set(range(1000)).issubset(seen), (
        'The timed loop did not traverse every document ID/index'
    )

    expected_mean = float(np.mean(durations))
    expected_sem = float(stats.sem(durations))
    critical = float(stats.t.ppf(0.975, df=999))
    expected_margin = critical * expected_sem
    actual_mean = float(generated_report['mean_time_sec'])
    actual_lower = float(generated_report['ci_lower'])
    actual_upper = float(generated_report['ci_upper'])
    actual_margin_low = actual_mean - actual_lower
    actual_margin_high = actual_upper - actual_mean

    assert math.isclose(actual_mean, expected_mean, rel_tol=1e-6, abs_tol=1e-10)
    assert math.isclose(actual_margin_low, expected_margin, rel_tol=1e-4, abs_tol=1e-10), (
        'ci_lower is not the 95% Student t confidence bound over the 1000 timings'
    )
    assert math.isclose(actual_margin_high, expected_margin, rel_tol=1e-4, abs_tol=1e-10), (
        'ci_upper is not the 95% Student t confidence bound over the 1000 timings'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
