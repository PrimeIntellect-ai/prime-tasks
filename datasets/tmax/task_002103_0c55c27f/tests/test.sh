#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import scipy.stats as stats

ORACLE = Path('/app/risk_evaluator')
TRUE_TRAIN_PATH = Path('/tmp/true_train_scores.csv')
TRUE_EVAL_PATH = Path('/tmp/true_scores_eval.csv')
TEST_CSV = Path('/tmp/test_logs_eval.csv')


def run_oracle(input_path, output_path):
    with open(output_path, 'w') as output:
        subprocess.run([str(ORACLE), str(input_path)], stdout=output, check=True)


@pytest.fixture(scope='session', autouse=True)
def prepare_hidden_evaluation():
    global TEST_DATA, TRUE_EVAL_DF

    assert ORACLE.is_file(), 'The oracle binary is missing.'
    run_oracle('/home/user/logs.csv', TRUE_TRAIN_PATH)

    fixed_messages = [
        'system error fail',
        'warning high temp',
        'success login',
        'timeout error',
        'fail fail fail',
        'no keywords here',
        'error warning success timeout fail',
        'ERROR uppercase',
        'multiple error error error',
        'success success',
    ]

    vocabulary = [
        'error', 'fail', 'warning', 'timeout', 'success',
        'system', 'startup', 'database', 'connection', 'disk',
        'usage', 'high', 'user', 'login', 'memory', 'allocation',
        'process', 'network', 'critical', 'normal', 'service',
    ]
    rng = random.SystemRandom()
    random_messages = []
    for _ in range(300):
        tokens = []
        for _ in range(rng.randint(1, 14)):
            token = rng.choice(vocabulary)
            if rng.random() < 0.30:
                token = token.upper()
            tokens.append(token)
        random_messages.append(' '.join(tokens))

    messages = fixed_messages + random_messages
    TEST_DATA = pd.DataFrame({
        'log_id': list(range(101, 101 + len(messages))),
        'message': messages,
    })
    TEST_DATA.to_csv(TEST_CSV, index=False)
    run_oracle(TEST_CSV, TRUE_EVAL_PATH)
    TRUE_EVAL_DF = pd.read_csv(TRUE_EVAL_PATH)

    # The agent was allowed to query the oracle while working, but the submitted
    # replacement must not invoke it during inference.
    old_mode = ORACLE.stat().st_mode & 0o777
    ORACLE.chmod(0o700)
    try:
        yield
    finally:
        ORACLE.chmod(old_mode)


def test_surrogate_script_exists():
    script_path = Path('/home/user/surrogate.py')
    assert script_path.exists(), 'The script /home/user/surrogate.py does not exist.'
    assert script_path.is_file(), '/home/user/surrogate.py is not a file.'


def test_mean_ci_correct():
    ci_path = Path('/home/user/mean_ci.txt')
    assert ci_path.exists(), '/home/user/mean_ci.txt does not exist.'

    logs_csv = Path('/home/user/logs.csv')
    assert logs_csv.exists(), '/home/user/logs.csv is missing.'

    df = pd.read_csv(TRUE_TRAIN_PATH)
    scores = df['risk_score'].values
    n = len(scores)
    mean = np.mean(scores)
    se = stats.sem(scores)
    ci = stats.t.interval(0.95, df=n - 1, loc=mean, scale=se)
    expected_ci_str = f'[{ci[0]:.4f}, {ci[1]:.4f}]'

    content = ci_path.read_text().strip()
    assert content == expected_ci_str, f'Expected CI: {expected_ci_str}, but found: {content}'


def test_surrogate_mse():
    pred_csv = Path('/tmp/pred_scores_eval.csv')
    trace_path = Path('/tmp/surrogate_exec.trace')
    pred_csv.unlink(missing_ok=True)
    trace_path.unlink(missing_ok=True)

    result = subprocess.run([
        '/usr/bin/strace', '-f', '-qq', '-e', 'trace=execve',
        '-o', str(trace_path),
        '/usr/sbin/runuser', '-u', 'user', '--',
        '/usr/bin/python3', '/home/user/surrogate.py', str(TEST_CSV), str(pred_csv),
    ], capture_output=True, text=True)
    assert result.returncode == 0, f'Surrogate script failed with error:\n{result.stderr}'

    # Only runuser and the requested Python interpreter may be executed. This
    # rejects wrappers that call the oracle, including renamed copies.
    trace = trace_path.read_text()
    successful_execs = re.findall(r'execve\("([^"]+)".*\)\s+=\s+0', trace)
    assert successful_execs == ['/usr/sbin/runuser', '/usr/bin/python3'], (
        f'Surrogate launched external executables during inference: {successful_execs}'
    )

    assert pred_csv.exists(), f'Surrogate script did not create the output file {pred_csv}'
    pred_df = pd.read_csv(pred_csv)

    assert list(pred_df.columns) == ['log_id', 'predicted_score'], (
        "Output CSV must contain exactly 'log_id' and 'predicted_score' columns."
    )
    assert len(pred_df) == len(TRUE_EVAL_DF), 'Mismatch in number of rows between true and predicted scores.'
    assert pred_df['log_id'].tolist() == TEST_DATA['log_id'].tolist(), (
        'Output log_id values must exactly match the input rows and order.'
    )
    assert pd.api.types.is_numeric_dtype(pred_df['predicted_score']), 'predicted_score must be numeric.'
    assert np.isfinite(pred_df['predicted_score'].to_numpy(dtype=float)).all(), (
        'predicted_score contains non-finite values.'
    )

    merged = pd.merge(TRUE_EVAL_DF, pred_df, on='log_id', validate='one_to_one')
    assert len(merged) == len(TRUE_EVAL_DF), 'Mismatch in number of rows between true and predicted scores.'

    mse = np.mean((merged['risk_score'] - merged['predicted_score']) ** 2)
    threshold = 0.05
    assert mse <= threshold, f'MSE is {mse:.4f}, which is greater than the threshold of {threshold}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
