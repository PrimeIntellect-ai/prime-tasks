#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GridSearchCV, KFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

PYTHON_SCRIPT = '/home/user/clean_and_tune.py'
BASH_SCRIPT = '/home/user/run_pipeline.sh'
DATA_PATH = '/home/user/housing_messy.csv'
LOG_PATH = '/home/user/reproducibility_log.txt'
CAPTURE_PATH = '/tmp/pipeline_env_capture.jsonl'
HOOK_DIR = '/tmp/verifier_python_hook'


def test_python_script_exists():
    """Test that the python script was created."""
    assert os.path.isfile(PYTHON_SCRIPT), "The file /home/user/clean_and_tune.py does not exist."


def test_bash_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    assert os.path.isfile(BASH_SCRIPT), f"The file {BASH_SCRIPT} does not exist."

    st = os.stat(BASH_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {BASH_SCRIPT} is not executable."


def test_bash_script_environment_variables():
    """Test that the bash script exports the required environment variables."""
    with open(BASH_SCRIPT, 'r') as f:
        content = f.read()

    required_vars = [
        r'OMP_NUM_THREADS\s*=\s*1',
        r'OPENBLAS_NUM_THREADS\s*=\s*1',
        r'MKL_NUM_THREADS\s*=\s*1',
        r'PYTHONHASHSEED\s*=\s*42'
    ]

    for var in required_vars:
        assert re.search(var, content), f"The bash script must set {var.split('=')[0].strip()}."

    # Retain the original assignment checks above, and also require the requested
    # export operation and execution of the requested Python artifact.
    for name, value in [
        ('OMP_NUM_THREADS', '1'),
        ('OPENBLAS_NUM_THREADS', '1'),
        ('MKL_NUM_THREADS', '1'),
        ('PYTHONHASHSEED', '42'),
    ]:
        pattern = rf'(?m)^\s*export\s+{name}\s*=\s*["\']?{value}["\']?\s*(?:#.*)?$'
        assert re.search(pattern, content), f"The bash script must export {name}={value}."

    assert re.search(r'clean_and_tune\.py', content), \
        "The bash script must execute /home/user/clean_and_tune.py."


def _make_hidden_dataset():
    seed = int.from_bytes(os.urandom(8), 'little')
    rng = np.random.default_rng(seed)
    n = 180
    rooms = rng.integers(2, 11, n)
    complete_age = rng.integers(1, 61, n).astype(float)
    income = rng.uniform(25000, 175000, n)
    price = (42000 + rooms * 18750 - complete_age * 875
             + income * 1.37 + rng.normal(0, 9000, n))
    age = complete_age.copy()
    age[rng.choice(n, 18, replace=False)] = np.nan
    pd.DataFrame({
        'rooms': rooms,
        'age': age,
        'income': income,
        'price': price,
    }).to_csv(DATA_PATH, index=False)


def _reference_result():
    df = pd.read_csv(DATA_PATH)
    median_age = df['age'].median()
    df['age'] = df['age'].fillna(median_age)
    df['rooms_per_age'] = df['rooms'] / df['age']
    X = df[['rooms', 'age', 'rooms_per_age', 'income']]
    y = df['price']

    pipeline = Pipeline([
        ('scaler', StandardScaler()),
        ('random_forest', RandomForestRegressor(
            n_estimators=50, random_state=42
        )),
    ])
    cv = KFold(n_splits=5, shuffle=True, random_state=42)
    search = GridSearchCV(
        pipeline,
        {'random_forest__max_depth': [3, 5, 7]},
        cv=cv,
    )
    search.fit(X, y)
    return int(search.best_params_['random_forest__max_depth']), float(search.best_score_)


def _install_environment_capture_hook():
    os.makedirs(HOOK_DIR, exist_ok=True)
    hook = r'''import json, os, sys
record = {
    "argv": list(sys.argv),
    "cwd": os.getcwd(),
    "env": {name: os.environ.get(name) for name in (
        "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "PYTHONHASHSEED"
    )},
}
with open("/tmp/pipeline_env_capture.jsonl", "a") as f:
    f.write(json.dumps(record) + "\n")
'''
    with open(os.path.join(HOOK_DIR, 'sitecustomize.py'), 'w') as f:
        f.write(hook)


def _run_pipeline_once():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    if os.path.exists(CAPTURE_PATH):
        os.remove(CAPTURE_PATH)

    env = os.environ.copy()
    for name in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS', 'PYTHONHASHSEED'):
        env.pop(name, None)
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = HOOK_DIR if not old_pythonpath else HOOK_DIR + os.pathsep + old_pythonpath

    result = subprocess.run(
        [BASH_SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=180,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "Running run_pipeline.sh did not create the log."
    assert os.path.isfile(CAPTURE_PATH), "The pipeline did not start a Python interpreter."

    with open(CAPTURE_PATH) as f:
        records = [json.loads(line) for line in f if line.strip()]

    clean_records = []
    for record in records:
        argv = record.get('argv') or []
        if not argv:
            continue
        arg0 = argv[0]
        if not os.path.isabs(arg0):
            arg0 = os.path.join(record.get('cwd', '/home/user'), arg0)
        if os.path.realpath(arg0) == os.path.realpath(PYTHON_SCRIPT):
            clean_records.append(record)

    assert clean_records, "run_pipeline.sh did not execute /home/user/clean_and_tune.py."
    expected_env = {
        'OMP_NUM_THREADS': '1',
        'OPENBLAS_NUM_THREADS': '1',
        'MKL_NUM_THREADS': '1',
        'PYTHONHASHSEED': '42',
    }
    assert any(record.get('env') == expected_env for record in clean_records), \
        "The required environment variables were not exported to clean_and_tune.py."

    with open(LOG_PATH, 'rb') as f:
        return f.read()


def test_pipeline_executes_reproducibly_and_matches_expected_result():
    original_data = None
    if os.path.exists(DATA_PATH):
        with open(DATA_PATH, 'rb') as f:
            original_data = f.read()

    try:
        _make_hidden_dataset()
        expected_depth, expected_score = _reference_result()
        _install_environment_capture_hook()

        first = _run_pipeline_once()
        second = _run_pipeline_once()
        assert first == second, "The pipeline log changed between identical runs."

        text = second.decode('utf-8')
        match = re.fullmatch(
            r'Best max_depth: ([+-]?\d+)\nBest CV score: ([+-]?(?:\d+(?:\.\d*)?|\.\d+))\n?',
            text,
        )
        assert match, "The log must contain exactly the required two-line format."
        assert int(match.group(1)) == expected_depth, "Best max_depth is incorrect."
        assert match.group(2) == f'{expected_score:.4f}', "Best CV score is incorrect."
    finally:
        if original_data is not None:
            with open(DATA_PATH, 'wb') as f:
                f.write(original_data)


def test_reproducibility_log_format_and_content():
    """Test that the reproducibility log exists and has the correct format."""
    assert os.path.isfile(LOG_PATH), f"The file {LOG_PATH} does not exist. Did you run the pipeline?"

    with open(LOG_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {LOG_PATH}, found {len(lines)}."

    assert lines[0].startswith("Best max_depth: "), "First line must start with 'Best max_depth: '"
    assert lines[1].startswith("Best CV score: "), "Second line must start with 'Best CV score: '"

    try:
        int(lines[0].split(":")[1].strip())
    except ValueError:
        pytest.fail("Could not parse integer for Best max_depth.")

    try:
        float(lines[1].split(":")[1].strip())
    except ValueError:
        pytest.fail("Could not parse float for Best CV score.")

    score_str = lines[1].split(":")[1].strip()
    if '.' in score_str:
        assert len(score_str.split('.')[1]) <= 4, "The CV score must be rounded to 4 decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
