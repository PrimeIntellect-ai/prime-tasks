#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PIPELINE = Path('/home/user/evaluation_pipeline')
DATA = Path('/home/user/data')
RESULTS = PIPELINE / 'results.json'


def run(cmd, cwd=PIPELINE, timeout=60):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def test_results_json_exists():
    assert RESULTS.is_file(), 'The results.json file was not generated in /home/user/evaluation_pipeline/.'


def test_results_json_contents():
    with RESULTS.open('r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('results.json is not a valid JSON file.')

    assert 'alpha' in data, "Key 'alpha' is missing from results.json."
    assert 'beta' in data, "Key 'beta' is missing from results.json."
    assert 'best_model' in data, "Key 'best_model' is missing from results.json."

    alpha = data['alpha']
    beta = data['beta']

    # Original Alpha expectations
    assert abs(alpha.get('fold_1_mse', -1) - 0.25) < 1e-4, f"Alpha fold_1_mse is incorrect. Got {alpha.get('fold_1_mse')}"
    assert abs(alpha.get('fold_2_mse', -1) - 0.25) < 1e-4, f"Alpha fold_2_mse is incorrect. Got {alpha.get('fold_2_mse')}"
    assert abs(alpha.get('fold_3_mse', -1) - 0.625) < 1e-4, f"Alpha fold_3_mse is incorrect. Got {alpha.get('fold_3_mse')}"
    assert abs(alpha.get('fold_4_mse', -1) - 1.0) < 1e-4, f"Alpha fold_4_mse is incorrect. Got {alpha.get('fold_4_mse')}"
    assert abs(alpha.get('fold_5_mse', -1) - 0.25) < 1e-4, f"Alpha fold_5_mse is incorrect. Got {alpha.get('fold_5_mse')}"
    assert abs(alpha.get('average_mse', -1) - 0.475) < 1e-4, f"Alpha average_mse is incorrect. Got {alpha.get('average_mse')}"

    # Original Beta expectations
    assert abs(beta.get('fold_1_mse', -1) - 3.125) < 1e-4, f"Beta fold_1_mse is incorrect. Got {beta.get('fold_1_mse')}"
    assert abs(beta.get('fold_2_mse', -1) - 1.625) < 1e-4, f"Beta fold_2_mse is incorrect. Got {beta.get('fold_2_mse')}"
    assert abs(beta.get('fold_3_mse', -1) - 5.125) < 1e-4, f"Beta fold_3_mse is incorrect. Got {beta.get('fold_3_mse')}"
    assert abs(beta.get('fold_4_mse', -1) - 25.0) < 1e-4, f"Beta fold_4_mse is incorrect. Got {beta.get('fold_4_mse')}"
    assert abs(beta.get('fold_5_mse', -1) - 5.125) < 1e-4, f"Beta fold_5_mse is incorrect. Got {beta.get('fold_5_mse')}"
    assert abs(beta.get('average_mse', -1) - 8.0) < 1e-4, f"Beta average_mse is incorrect. Got {beta.get('average_mse')}"

    assert data['best_model'] == 'alpha', f"Expected best_model to be 'alpha', got '{data['best_model']}'"


def test_go_files_exist():
    assert (PIPELINE / 'main.go').is_file(), 'main.go is missing from /home/user/evaluation_pipeline/.'
    assert (PIPELINE / 'math_test.go').is_file(), 'math_test.go is missing from /home/user/evaluation_pipeline/.'
    assert (PIPELINE / 'go.mod').is_file(), 'go.mod is missing from /home/user/evaluation_pipeline/.'


def test_go_tests_pass():
    result = run(['go', 'test', '-count=1'])
    assert result.returncode == 0, f"'go test' failed in {PIPELINE}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def _write_csv(path, fields, rows):
    with path.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def _expected(records):
    result = {}
    averages = {}
    for model in ('alpha', 'beta'):
        block = {}
        fold_values = []
        for fold in range(1, 6):
            rows = [r for r in records if r['fold'] == fold]
            mse = sum((r[model] - r['truth']) ** 2 for r in rows) / len(rows)
            block[f'fold_{fold}_mse'] = mse
            fold_values.append(mse)
        block['average_mse'] = sum(fold_values) / 5.0
        averages[model] = block['average_mse']
        result[model] = block
    result['best_model'] = 'alpha' if averages['alpha'] < averages['beta'] else 'beta'
    return result


def _assert_generated_result(expected):
    assert RESULTS.is_file(), 'Running the Go program did not generate results.json.'
    with RESULTS.open() as f:
        data = json.load(f)
    assert set(data) == {'alpha', 'beta', 'best_model'}, 'results.json has an incorrect top-level structure.'
    metric_keys = {*(f'fold_{i}_mse' for i in range(1, 6)), 'average_mse'}
    for model in ('alpha', 'beta'):
        assert isinstance(data[model], dict)
        assert set(data[model]) == metric_keys, f'Incorrect metric structure for {model}.'
        for key in metric_keys:
            value = data[model][key]
            assert isinstance(value, (int, float)) and not isinstance(value, bool)
            assert math.isfinite(value)
            assert abs(value - expected[model][key]) <= 5.01e-5, (
                f'{model}.{key} is incorrect for verifier-generated input: '
                f'got {value}, expected {expected[model][key]:.4f}'
            )
    assert data['best_model'] == expected['best_model']


def _make_case(alpha_wins):
    rng = random.Random(secrets.randbits(128))
    records = []
    used = set()
    counts = [1, 2, 4, 3, 5]
    for fold, count in enumerate(counts, 1):
        for j in range(count):
            ident = rng.randrange(1000, 900000)
            while ident in used:
                ident = rng.randrange(1000, 900000)
            used.add(ident)
            truth = rng.randrange(-3000, 5000) / 20.0
            small = rng.choice([-1, 1]) * rng.randrange(1, 16) / 10.0
            large = rng.choice([-1, 1]) * rng.randrange(35, 100) / 10.0
            alpha_err, beta_err = (small, large) if alpha_wins else (large, small)
            records.append({
                'id': ident,
                'fold': fold,
                'truth': truth,
                'alpha': truth + alpha_err,
                'beta': truth + beta_err,
            })
    return records


def _install_case(records):
    truths = [{'id': r['id'], 'fold_id': r['fold'], 'true_value': r['truth']} for r in records]
    alpha = [{'id': r['id'], 'pred_value': r['alpha']} for r in records]
    beta = [{'id': r['id'], 'pred_value': r['beta']} for r in records]
    random.SystemRandom().shuffle(truths)
    random.SystemRandom().shuffle(alpha)
    random.SystemRandom().shuffle(beta)
    _write_csv(DATA / 'ground_truth.csv', ['id', 'fold_id', 'true_value'], truths)
    _write_csv(DATA / 'preds_alpha.csv', ['id', 'pred_value'], alpha)
    _write_csv(DATA / 'preds_beta.csv', ['id', 'pred_value'], beta)


def test_program_executes_and_computes_from_csv_inputs():
    paths = [DATA / 'ground_truth.csv', DATA / 'preds_alpha.csv', DATA / 'preds_beta.csv']
    originals = {p: p.read_bytes() for p in paths}
    try:
        for alpha_wins in (True, False):
            records = _make_case(alpha_wins)
            _install_case(records)
            if RESULTS.exists():
                RESULTS.unlink()
            result = run(['go', 'run', '.'])
            assert result.returncode == 0, (
                f"'go run .' failed on verifier-generated CSV input.\n"
                f'Stdout: {result.stdout}\nStderr: {result.stderr}'
            )
            _assert_generated_result(_expected(records))
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
        if RESULTS.exists():
            RESULTS.unlink()
        result = run(['go', 'run', '.'])
        assert result.returncode == 0, (
            f"'go run .' failed after restoring the supplied CSV files.\n"
            f'Stdout: {result.stdout}\nStderr: {result.stderr}'
        )


def _matching_brace(source, opening):
    depth = 0
    i = opening
    state = 'code'
    while i < len(source):
        c = source[i]
        n = source[i + 1] if i + 1 < len(source) else ''
        if state == 'code':
            if c == '/' and n == '/':
                state = 'line'; i += 2; continue
            if c == '/' and n == '*':
                state = 'block'; i += 2; continue
            if c == '"': state = 'string'
            elif c == "'": state = 'rune'
            elif c == '`': state = 'raw'
            elif c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0: return i
        elif state == 'line':
            if c == '\n': state = 'code'
        elif state == 'block':
            if c == '*' and n == '/': state = 'code'; i += 2; continue
        elif state in ('string', 'rune'):
            if c == '\\': i += 2; continue
            if (state == 'string' and c == '"') or (state == 'rune' and c == "'"): state = 'code'
        elif state == 'raw' and c == '`':
            state = 'code'
        i += 1
    raise AssertionError('Could not parse a Go function body.')


def _function_span(source, match):
    opening = source.find('{', match.end())
    assert opening >= 0
    return opening, _matching_brace(source, opening)


def test_math_tests_exercise_numerical_mse_behavior():
    test_path = PIPELINE / 'math_test.go'
    test_source = test_path.read_text()
    test_matches = list(re.finditer(r'(?m)^\s*func\s+(Test[A-Za-z0-9_]*)\s*\(\s*[A-Za-z_]\w*\s+\*testing\.T\s*\)', test_source))
    assert len(test_matches) >= 2, 'math_test.go must define at least two Go unit tests.'
    test_names = [m.group(1) for m in test_matches]

    declarations = []
    for path in PIPELINE.glob('*.go'):
        if path.name.endswith('_test.go'):
            continue
        source = path.read_text()
        for match in re.finditer(r'(?m)^\s*func\s+([A-Za-z_]\w*)\s*\(', source):
            if match.group(1) != 'main':
                declarations.append((path, source, match, match.group(1)))

    assert declarations, 'No production calculation function was found.'
    successful = False
    diagnostics = []
    for path, source, match, name in declarations:
        if len(re.findall(r'\b' + re.escape(name) + r'\s*\(', test_source)) < 2:
            continue
        opening, closing = _function_span(source, match)
        original_bytes = path.read_bytes()
        caught_by = {}
        candidate_valid = True
        try:
            for label, replacement in [('zero', ' return 0 '), ('wrong', ' return 123456.789 ')]:
                mutated = source[:opening + 1] + replacement + source[closing:]
                path.write_text(mutated)
                compile_result = run(['go', 'test', '-run', '^$', '-count=1'])
                if compile_result.returncode != 0:
                    candidate_valid = False
                    break
                failures = set()
                for test_name in test_names:
                    result = run(['go', 'test', '-run', '^' + test_name + '$', '-count=1'])
                    if result.returncode != 0:
                        failures.add(test_name)
                caught_by[label] = failures
        finally:
            path.write_bytes(original_bytes)

        if candidate_valid:
            zero_caught = caught_by.get('zero', set())
            wrong_caught = caught_by.get('wrong', set())
            if zero_caught and wrong_caught and len(zero_caught | wrong_caught) >= 2:
                successful = True
                break
            diagnostics.append(f'{name}: zero caught by {sorted(zero_caught)}, wrong value caught by {sorted(wrong_caught)}')

    assert successful, (
        'The submitted math tests must call a production MSE function in at least two tests, '
        'and must reject both an always-zero implementation and a clearly incorrect nonzero implementation. '
        + '; '.join(diagnostics)
    )

    result = run(['go', 'test', '-count=1'])
    assert result.returncode == 0, f'Go tests failed after mutation checks.\n{result.stdout}\n{result.stderr}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
