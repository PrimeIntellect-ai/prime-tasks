#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

PIPELINE_RUNS_PATH = '/home/user/pipeline_runs.jsonl'
DATA_PATH = '/home/user/data/server_metrics.jsonl'
EXPECTED_CONFIGS = {
    (42, 1.0),
    (42, 0.1),
    (99, 1.0)
}


def load_xy(path):
    X, y = [], []
    with open(path, 'r') as f:
        for line in f:
            record = json.loads(line)
            metrics = record['metrics']
            X.append([
                metrics['cpu_utilization'],
                metrics['memory_gb'],
                metrics['disk_io'],
            ])
            y.append(1 if record['status']['error_code'] > 0 else 0)
    return X, y


def expected_accuracy(path, seed, c_value):
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score
    from sklearn.model_selection import train_test_split
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler

    X, y = load_xy(path)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=seed
    )
    model = Pipeline([
        ('scaler', StandardScaler()),
        ('classifier', LogisticRegression(C=c_value, random_state=seed)),
    ])
    model.fit(X_train, y_train)
    return round(float(accuracy_score(y_test, model.predict(X_test))), 4)


def read_records(path):
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    if lines == ['']:
        return []
    return [json.loads(line) for line in lines]


def validate_records(records, expected):
    assert len(records) == len(expected)
    seen = set()
    for record in records:
        assert set(record.keys()) == {'seed', 'C', 'accuracy'}
        assert isinstance(record['seed'], int)
        assert isinstance(record['C'], (int, float))
        assert isinstance(record['accuracy'], (int, float))
        assert math.isfinite(float(record['accuracy']))
        assert 0.0 <= record['accuracy'] <= 1.0
        assert record['accuracy'] == round(record['accuracy'], 4)
        key = (record['seed'], float(record['C']))
        assert key in expected
        assert key not in seen
        assert float(record['accuracy']) == expected[key]
        seen.add(key)
    assert seen == set(expected)


def make_challenge_dataset():
    rng = secrets.SystemRandom()
    records = []
    for i in range(360):
        cpu = rng.uniform(-2.5, 2.5)
        memory = rng.uniform(0.001, 0.009)
        disk = rng.uniform(100000.0, 900000.0)
        score = 1.35 * cpu + 700.0 * (memory - 0.005) - 0.000004 * (disk - 500000.0)
        score += rng.uniform(-1.1, 1.1)
        is_error = score > 0
        records.append({
            'timestamp': f'challenge-{i}',
            'metrics': {
                'cpu_utilization': cpu,
                'memory_gb': memory,
                'disk_io': disk,
                'network_drop': rng.randrange(0, 1000),
            },
            'status': {
                'error_code': rng.choice([404, 500, 503]) if is_error else rng.choice([0, -7]),
                'message': 'unused',
            },
        })
    return ''.join(json.dumps(record) + '\n' for record in records).encode()


def candidate_command(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.js':
        return ['node', str(path)]
    if suffix == '.rb':
        return ['ruby', str(path)]
    if suffix == '.pl':
        return ['perl', str(path)]
    if suffix == '.jar':
        return ['java', '-jar', str(path)]
    try:
        first = path.read_bytes()[:128]
    except OSError:
        return None
    if first.startswith(b'#!'):
        if b'python' in first.splitlines()[0]:
            return ['python3', str(path)]
        if b'bash' in first.splitlines()[0] or b'/sh' in first.splitlines()[0]:
            return ['bash', str(path)]
    if path.stat().st_mode & stat.S_IXUSR:
        return [str(path)]
    return None


def find_candidates():
    candidates = []
    root = Path('/home/user')
    for path in root.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        rel = path.relative_to(root)
        if any(part.startswith('.') for part in rel.parts):
            continue
        if str(path) in {DATA_PATH, PIPELINE_RUNS_PATH} or 'data' in rel.parts:
            continue
        command = candidate_command(path)
        if command is None:
            continue
        name = path.name.lower()
        priority = 0 if any(word in name for word in ('pipeline', 'model', 'etl', 'train')) else 1
        candidates.append((priority, len(rel.parts), str(path), command))
    candidates.sort()
    return [item[3] for item in candidates[:50]]


def run_once(base_command, arg_style, seed, c_value):
    if arg_style == 'positional':
        args = [str(seed), str(c_value)]
    elif arg_style == 'flags':
        args = ['--seed', str(seed), '--C', str(c_value)]
    else:
        args = ['--random-seed', str(seed), '--C', str(c_value)]
    subprocess.run(
        base_command + args,
        cwd='/home/user',
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        check=True,
        env={**os.environ, 'HOME': '/home/user'},
    )


def exercise_pipeline():
    original_data = Path(DATA_PATH).read_bytes()
    challenge_data = make_challenge_dataset()
    challenge_seed, challenge_c = 314159, 0.37
    errors = []

    try:
        for command in find_candidates():
            for arg_style in ('positional', 'flags', 'random-seed-flag'):
                try:
                    Path(DATA_PATH).write_bytes(challenge_data)
                    if os.path.lexists(PIPELINE_RUNS_PATH):
                        os.remove(PIPELINE_RUNS_PATH)
                    challenge_expected = {
                        (challenge_seed, challenge_c): expected_accuracy(
                            DATA_PATH, challenge_seed, challenge_c
                        )
                    }
                    run_once(command, arg_style, challenge_seed, challenge_c)
                    assert os.path.isfile(PIPELINE_RUNS_PATH)
                    validate_records(read_records(PIPELINE_RUNS_PATH), challenge_expected)

                    Path(DATA_PATH).write_bytes(original_data)
                    if os.path.lexists(PIPELINE_RUNS_PATH):
                        os.remove(PIPELINE_RUNS_PATH)
                    expected = {
                        (seed, c_value): expected_accuracy(DATA_PATH, seed, c_value)
                        for seed, c_value in [(42, 1.0), (42, 0.1), (99, 1.0)]
                    }
                    for seed, c_value in [(42, 1.0), (42, 0.1), (99, 1.0)]:
                        run_once(command, arg_style, seed, c_value)
                    assert os.path.isfile(PIPELINE_RUNS_PATH)
                    validate_records(read_records(PIPELINE_RUNS_PATH), expected)
                    return command, expected
                except Exception as exc:
                    errors.append(f"{' '.join(command)} ({arg_style}): {exc}")
        pytest.fail('No submitted pipeline artifact successfully processed both the hidden and required datasets. ' + '; '.join(errors[-8:]))
    finally:
        Path(DATA_PATH).write_bytes(original_data)


EXECUTED_COMMAND, RECOMPUTED_EXPECTED = exercise_pipeline()


def test_pipeline_runs_exists():
    assert os.path.exists(PIPELINE_RUNS_PATH), f"The file {PIPELINE_RUNS_PATH} does not exist."
    assert os.path.isfile(PIPELINE_RUNS_PATH), f"The path {PIPELINE_RUNS_PATH} is not a file."


def test_pipeline_runs_content():
    assert os.path.exists(PIPELINE_RUNS_PATH), f"The file {PIPELINE_RUNS_PATH} does not exist."

    with open(PIPELINE_RUNS_PATH, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 3, f"Expected exactly 3 lines in {PIPELINE_RUNS_PATH}, found {len(lines)}."

    found_configs = set()
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {PIPELINE_RUNS_PATH} is not valid JSON.")

        assert "seed" in record, f"Line {i+1} missing 'seed' key."
        assert "C" in record, f"Line {i+1} missing 'C' key."
        assert "accuracy" in record, f"Line {i+1} missing 'accuracy' key."
        assert set(record) == {'seed', 'C', 'accuracy'}, f"Line {i+1} must contain exactly the required keys."

        seed = record["seed"]
        c_val = record["C"]
        accuracy = record["accuracy"]

        assert isinstance(seed, int), f"Line {i+1}: 'seed' must be an integer."
        assert isinstance(c_val, (int, float)), f"Line {i+1}: 'C' must be a float."
        assert isinstance(accuracy, (int, float)), f"Line {i+1}: 'accuracy' must be a float."

        assert 0.0 <= accuracy <= 1.0, f"Line {i+1}: 'accuracy' must be between 0.0 and 1.0."
        assert math.isfinite(float(accuracy)), f"Line {i+1}: 'accuracy' must be finite."
        assert accuracy == round(accuracy, 4), f"Line {i+1}: 'accuracy' must be rounded to 4 decimal places."

        config = (seed, float(c_val))
        assert config in RECOMPUTED_EXPECTED, f"Line {i+1}: unexpected experiment configuration {config}."
        assert float(accuracy) == RECOMPUTED_EXPECTED[config], (
            f"Line {i+1}: expected recomputed accuracy {RECOMPUTED_EXPECTED[config]}, found {accuracy}."
        )
        found_configs.add(config)

    missing_configs = EXPECTED_CONFIGS - found_configs
    extra_configs = found_configs - EXPECTED_CONFIGS

    assert not missing_configs, f"Missing expected experiment configurations: {missing_configs}"
    assert not extra_configs, f"Found unexpected experiment configurations: {extra_configs}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
