#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT = '/home/user/analyze.py'
DATASET = '/home/user/experiments.jsonl'
REPORT = '/home/user/report.json'
TARGET = 'ResNet50 using AdamW optimizer, learning_rate=0.001, batch=32'


def run_script():
    subprocess.run(['python3', SCRIPT], check=True, timeout=60, cwd='/home/user')


def load_report():
    with open(REPORT, 'r') as f:
        return json.load(f)


def expected_report(records):
    vectorizer = TfidfVectorizer(lowercase=True, stop_words='english')
    matrix = vectorizer.fit_transform([r['description'] for r in records] + [TARGET])
    similarities = cosine_similarity(matrix[-1], matrix[:-1]).ravel()
    order = sorted(range(len(records)), key=lambda i: (-float(similarities[i]), i))[:3]
    combined = np.asarray(
        [value for i in order for value in records[i]['metrics']], dtype=float
    )

    np.random.seed(42)
    bootstrap_means = []
    for _ in range(10000):
        sample = np.random.choice(combined, size=combined.size, replace=True)
        bootstrap_means.append(np.mean(sample))

    bootstrap_means = np.asarray(bootstrap_means)
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])
    return {
        'top_3_exp_ids': [records[i]['exp_id'] for i in order],
        'bootstrap_mean': round(float(np.mean(bootstrap_means)), 4),
        'ci_lower': round(float(lower), 4),
        'ci_upper': round(float(upper), 4),
    }


def write_records(records):
    with open(DATASET, 'w') as f:
        for record in records:
            f.write(json.dumps(record) + '\n')


def assert_report_matches(records):
    run_script()
    assert load_report() == expected_report(records)


def test_analyze_script_exists():
    assert os.path.exists(SCRIPT), f'Script {SCRIPT} does not exist.'
    assert os.path.isfile(SCRIPT), f'{SCRIPT} is not a file.'


def test_script_has_required_seed_placement_and_iteration_count():
    with open(SCRIPT, 'r') as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    seed_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or len(node.args) != 1:
            continue
        func = node.func
        if (isinstance(func, ast.Attribute) and func.attr == 'seed' and
                isinstance(func.value, ast.Attribute) and func.value.attr == 'random' and
                isinstance(node.args[0], ast.Constant) and node.args[0].value == 42):
            seed_calls.append(node)
    assert len(seed_calls) == 1, 'numpy.random.seed(42) must be called exactly once.'

    found_adjacent_loop = False
    found_10000_loop = False
    for parent in ast.walk(tree):
        for _, value in ast.iter_fields(parent):
            if not isinstance(value, list):
                continue
            for index, statement in enumerate(value[:-1]):
                if not (isinstance(statement, ast.Expr) and statement.value is seed_calls[0]):
                    continue
                loop = value[index + 1]
                if isinstance(loop, (ast.For, ast.While)):
                    found_adjacent_loop = True
                    if isinstance(loop, ast.For) and isinstance(loop.iter, ast.Call):
                        call = loop.iter
                        if (isinstance(call.func, ast.Name) and call.func.id == 'range' and
                                any(isinstance(arg, ast.Constant) and arg.value == 10000
                                    for arg in call.args)):
                            found_10000_loop = True
                    if isinstance(loop, ast.While):
                        if any(isinstance(n, ast.Constant) and n.value == 10000
                               for n in ast.walk(loop.test)):
                            found_10000_loop = True
    assert found_adjacent_loop, 'numpy.random.seed(42) must be immediately before the bootstrap loop.'
    assert found_10000_loop, 'The bootstrap loop must run exactly 10000 iterations.'


def test_report_exists_and_format():
    run_script()
    assert os.path.exists(REPORT), f'Report file {REPORT} does not exist. Did the script run successfully?'

    with open(REPORT, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{REPORT} is not valid JSON.'

    expected_keys = {'top_3_exp_ids', 'bootstrap_mean', 'ci_lower', 'ci_upper'}
    actual_keys = set(report.keys())
    assert actual_keys == expected_keys, f'Report keys do not match. Expected {expected_keys}, got {actual_keys}'

    assert isinstance(report['top_3_exp_ids'], list), 'top_3_exp_ids must be a list of strings.'
    assert len(report['top_3_exp_ids']) == 3, f"top_3_exp_ids must contain exactly 3 elements, got {len(report['top_3_exp_ids'])}."

    for val in ['bootstrap_mean', 'ci_lower', 'ci_upper']:
        assert isinstance(report[val], (int, float)), f'{val} must be a number.'

    assert report['ci_lower'] <= report['bootstrap_mean'], 'ci_lower must be less than or equal to bootstrap_mean.'
    assert report['bootstrap_mean'] <= report['ci_upper'], 'bootstrap_mean must be less than or equal to ci_upper.'


def test_report_values_plausible_and_correct():
    report = load_report()
    assert 0.69 <= report['bootstrap_mean'] <= 0.89, f"bootstrap_mean {report['bootstrap_mean']} is out of plausible bounds based on the dataset."
    assert 0.69 <= report['ci_lower'] <= 0.89, f"ci_lower {report['ci_lower']} is out of plausible bounds."
    assert 0.69 <= report['ci_upper'] <= 0.89, f"ci_upper {report['ci_upper']} is out of plausible bounds."

    valid_exp_ids = {'EXP_001', 'EXP_002', 'EXP_003', 'EXP_004', 'EXP_005', 'EXP_006'}
    for exp_id in report['top_3_exp_ids']:
        assert exp_id in valid_exp_ids, f'Invalid exp_id {exp_id} found in top_3_exp_ids.'

    with open(DATASET, 'r') as f:
        original_records = [json.loads(line) for line in f if line.strip()]
    assert report == expected_report(original_records)


def test_script_recomputes_results_for_changed_input():
    with open(DATASET, 'rb') as f:
        original_data = f.read()

    alternate_sets = [
        [
            {'exp_id': 'ALT_A', 'description': TARGET, 'metrics': [0.11, 0.19, 0.27, 0.35]},
            {'exp_id': 'ALT_B', 'description': 'ResNet50 using AdamW optimizer learning_rate=0.001 batch=64', 'metrics': [0.51, 0.58, 0.62]},
            {'exp_id': 'ALT_C', 'description': 'ResNet50 using AdamW optimizer learning_rate=0.9', 'metrics': [0.73, 0.77]},
            {'exp_id': 'ALT_D', 'description': 'Transformer encoder with SGD for translation', 'metrics': [0.91, 0.92]},
            {'exp_id': 'ALT_E', 'description': 'Random forest classification trees', 'metrics': [0.41, 0.42]},
        ],
        [
            {'exp_id': 'RUN_10', 'description': 'ResNet50 AdamW batch=32', 'metrics': [0.22, 0.31, 0.47]},
            {'exp_id': 'RUN_20', 'description': 'AdamW optimizer learning_rate=0.001 batch=32', 'metrics': [0.66, 0.71, 0.79, 0.83]},
            {'exp_id': 'RUN_30', 'description': 'ResNet50 using optimizer batch=16', 'metrics': [0.52, 0.57]},
            {'exp_id': 'RUN_40', 'description': 'VGG image model RMSprop', 'metrics': [0.95, 0.96]},
            {'exp_id': 'RUN_50', 'description': 'linear regression baseline', 'metrics': [0.12, 0.13]},
        ],
    ]

    try:
        for records in alternate_sets:
            write_records(records)
            assert_report_matches(records)
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_data)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
