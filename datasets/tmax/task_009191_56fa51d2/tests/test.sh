#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import stat
import subprocess

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

HOME = '/home/user'
DATA_DIR = os.path.join(HOME, 'data')
OUTPUTS = [os.path.join(HOME, 'bootstrap_ci.txt'), os.path.join(HOME, 'rmse.txt')]

ORIGINAL = {
    'sensors.csv': '''sensor_id,location,installation_year
1,North,2015
2,South,2016
,East,2017
4,West,2018
5,Central,2019
''',
    'readings.csv': '''sensor_id,timestamp,value
1,2023-01-01,10.5
2,2023-01-01,12.2
4,2023-01-01,9.8
5,2023-01-01,11.1
6,2023-01-01,15.0
''',
    'targets.csv': '''sensor_id,target_metric
1,105
2,120
4,95
5,110
''',
}

ALTERNATE = {
    'sensors.csv': '''sensor_id,location,installation_year
10,Alpha,2001
20,Beta,2003
,Gamma,2005
30,Delta,2008
40,Epsilon,2012
50,Zeta,2020
''',
    'readings.csv': '''sensor_id,timestamp,value
10,2024-01-01,2.5
20,2024-01-01,8.0
30,2024-01-01,-1.0
40,2024-01-01,4.25
50,2024-01-01,12.0
60,2024-01-01,99.0
''',
    'targets.csv': '''sensor_id,target_metric
10,7
20,19
30,-2
40,13
50,28
''',
}


def write_scenario(files):
    os.makedirs(DATA_DIR, exist_ok=True)
    for name, content in files.items():
        with open(os.path.join(DATA_DIR, name), 'w') as f:
            f.write(content)


def expected_results(files):
    sensors = pd.read_csv(io.StringIO(files['sensors.csv']))
    readings = pd.read_csv(io.StringIO(files['readings.csv']))
    targets = pd.read_csv(io.StringIO(files['targets.csv']))

    sensors = sensors.dropna(subset=['sensor_id']).copy()
    sensors['sensor_id'] = sensors['sensor_id'].astype(int)
    joined = sensors.merge(readings, on='sensor_id', how='inner').merge(
        targets, on='sensor_id', how='inner'
    )

    values = joined['value'].to_numpy()
    np.random.seed(42)
    bootstrap_means = [
        np.mean(np.random.choice(values, size=len(values), replace=True))
        for _ in range(1000)
    ]
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])
    expected_ci = f'{lower:.4f},{upper:.4f}'

    features = joined[['value', 'installation_year']]
    target = joined['target_metric']
    predictions = LinearRegression().fit(features, target).predict(features)
    rmse = np.sqrt(np.mean((predictions - target.to_numpy()) ** 2))
    return expected_ci, f'{rmse:.4f}'


def find_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__'}]
        for name in files:
            path = os.path.join(root, name)
            try:
                mode = os.lstat(path).st_mode
                if not stat.S_ISREG(mode) or os.path.islink(path):
                    continue
                is_python = name.endswith('.py')
                if not is_python:
                    with open(path, 'rb') as f:
                        first_line = f.readline(200).lower()
                    is_python = first_line.startswith(b'#!') and b'python' in first_line
                if is_python and os.path.getsize(path) > 0:
                    candidates.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(set(candidates))


def run_case(script, files):
    write_scenario(files)
    for output in OUTPUTS:
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        ['python3', script],
        cwd=HOME,
        env={**os.environ, 'HOME': HOME},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'{script} exited with {completed.returncode}: {completed.stderr[-1000:]}'
    )

    expected_ci, expected_rmse = expected_results(files)

    ci_path = '/home/user/bootstrap_ci.txt'
    assert os.path.isfile(ci_path), (
        f'Expected file {ci_path} is missing. The bootstrap CI results were not saved.'
    )
    with open(ci_path) as f:
        actual_ci = f.read().strip()
    assert actual_ci == expected_ci, (
        f'Content of {ci_path} is incorrect. Expected {expected_ci!r}, got {actual_ci!r}.'
    )

    rmse_path = '/home/user/rmse.txt'
    assert os.path.isfile(rmse_path), (
        f'Expected file {rmse_path} is missing. The RMSE result was not saved.'
    )
    with open(rmse_path) as f:
        actual_rmse = f.read().strip()
    assert actual_rmse == expected_rmse, (
        f'Content of {rmse_path} is incorrect. Expected {expected_rmse!r}, got {actual_rmse!r}.'
    )


def test_python_script_executes_full_analysis():
    scripts = find_scripts()
    assert scripts, 'No Python analysis script was found under /home/user.'

    failures = []
    successful_script = None
    try:
        for script in scripts[:50]:
            try:
                run_case(script, ORIGINAL)
                run_case(script, ALTERNATE)
                successful_script = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert successful_script is not None, (
            'No submitted Python script produced the derived bootstrap CI and RMSE '
            'for both datasets. ' + ' | '.join(failures[-10:])
        )

        # Leave the requested artifacts containing results for the original datasets.
        run_case(successful_script, ORIGINAL)
    finally:
        write_scenario(ORIGINAL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
