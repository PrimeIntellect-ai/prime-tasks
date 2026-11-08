#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import re
import subprocess
import pytest

SYSMETRICS = '/home/user/sysmetrics'
ANALYZER = os.path.join(SYSMETRICS, 'analyzer.go')
GO_MOD = os.path.join(SYSMETRICS, 'go.mod')
RESULTS = os.path.join(SYSMETRICS, 'results.json')
BINARY = '/tmp/sysmetrics_analyzer_test'


def read_csv(filepath):
    data = {'cpu': [], 'mem': [], 'net_in': [], 'net_out': []}
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data['cpu'].append(float(row['CPU_Usage']))
            data['mem'].append(float(row['Memory_Usage']))
            data['net_in'].append(float(row['Network_In']))
            data['net_out'].append(float(row['Network_Out']))
    return data


def mean(lst):
    return sum(lst) / len(lst)


def pearson_corr(x, y):
    mean_x = mean(x)
    mean_y = mean(y)
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    return num / math.sqrt(den_x * den_y)


def linreg_slope(x, y):
    mean_x = mean(x)
    mean_y = mean(y)
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den = sum((xi - mean_x) ** 2 for xi in x)
    return num / den


def cos_sim(v1, v2):
    dot = sum(x * y for x, y in zip(v1, v2))
    norm1 = math.sqrt(sum(x * x for x in v1))
    norm2 = math.sqrt(sum(x * x for x in v2))
    return dot / (norm1 * norm2)


def test_analyzer_exists_compiles_runs_and_generates_results():
    assert os.path.isfile(ANALYZER), 'The Go program /home/user/sysmetrics/analyzer.go was not found.'
    assert os.path.isfile(GO_MOD), 'The Go module file /home/user/sysmetrics/go.mod was not found.'

    build = subprocess.run(
        ['go', 'build', '-o', BINARY, 'analyzer.go'],
        cwd=SYSMETRICS,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert build.returncode == 0, f'The Go program did not compile successfully:\n{build.stdout}{build.stderr}'

    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    try:
        run = subprocess.run(
            [BINARY],
            cwd=SYSMETRICS,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert run.returncode == 0, f'The compiled Go program did not run successfully:\n{run.stdout}{run.stderr}'
        assert os.path.isfile(RESULTS), 'Running analyzer.go did not generate /home/user/sysmetrics/results.json.'
    finally:
        if os.path.exists(BINARY):
            os.remove(BINARY)


def test_results_json_exists():
    assert os.path.exists('/home/user/sysmetrics/results.json'), 'The output file /home/user/sysmetrics/results.json was not found.'


def test_results_json_content():
    results_file = '/home/user/sysmetrics/results.json'
    assert os.path.exists(results_file), 'The output file /home/user/sysmetrics/results.json was not found.'

    with open(results_file, 'r') as f:
        raw_results = f.read()

    try:
        results = json.loads(raw_results)
    except json.JSONDecodeError:
        pytest.fail('The file /home/user/sysmetrics/results.json is not valid JSON.')

    required_keys = ['correlation_A', 'regression_slope_B', 'cosine_similarity_AC']
    for key in required_keys:
        assert key in results, f"Key '{key}' is missing from the JSON results."
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool), f"Value for '{key}' must be a number."
        key_occurrences = re.findall(rf'"{re.escape(key)}"\s*:', raw_results)
        assert len(key_occurrences) == 1, f"Key '{key}' must appear exactly once in the JSON results."
        formatted = re.search(rf'"{re.escape(key)}"\s*:\s*-?\d+\.\d{{4}}(?=\s*[,}}])', raw_results)
        assert formatted is not None, f"Value for '{key}' must be written with exactly 4 decimal places."

    # Compute truth
    dataA = read_csv('/home/user/data/serverA.csv')
    dataB = read_csv('/home/user/data/serverB.csv')
    dataC = read_csv('/home/user/data/serverC.csv')

    corr_A = pearson_corr(dataA['cpu'], dataA['mem'])
    slope_B = linreg_slope(dataB['mem'], dataB['cpu'])

    vecA = [mean(dataA['cpu']), mean(dataA['mem']), mean(dataA['net_in']), mean(dataA['net_out'])]
    vecC = [mean(dataC['cpu']), mean(dataC['mem']), mean(dataC['net_in']), mean(dataC['net_out'])]
    cos_AC = cos_sim(vecA, vecC)

    expected_corr_A = round(corr_A, 4)
    expected_slope_B = round(slope_B, 4)
    expected_cos_AC = round(cos_AC, 4)

    assert math.isclose(results['correlation_A'], expected_corr_A, abs_tol=1e-4), \
        f"correlation_A is incorrect. Expected {expected_corr_A}, got {results['correlation_A']}."

    assert math.isclose(results['regression_slope_B'], expected_slope_B, abs_tol=1e-4), \
        f"regression_slope_B is incorrect. Expected {expected_slope_B}, got {results['regression_slope_B']}."

    assert math.isclose(results['cosine_similarity_AC'], expected_cos_AC, abs_tol=1e-4), \
        f"cosine_similarity_AC is incorrect. Expected {expected_cos_AC}, got {results['cosine_similarity_AC']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
