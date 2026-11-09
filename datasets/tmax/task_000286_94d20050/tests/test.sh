#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import inspect
import os
import shutil
import sqlite3
import subprocess
import tempfile

PIPELINE = '/home/user/pipeline.sh'
PROCESSOR = '/home/user/process_data.py'
DATABASE = '/home/user/data.db'
OUTPUT = '/home/user/final_ema.txt'


def expected_ema(prices, alpha=0.1):
    if not prices:
        return 0.0
    ema = prices[0]
    for price in prices[1:]:
        ema = (price * alpha) + (ema * (1 - alpha))
    return ema


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [PIPELINE],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'pipeline.sh failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT), f'The output file {OUTPUT} does not exist. Did you run the pipeline?'
    return open(OUTPUT, 'r').read().strip()


def replace_prices(rows):
    conn = sqlite3.connect(DATABASE)
    try:
        conn.execute('DROP TABLE IF EXISTS daily_prices')
        conn.execute('CREATE TABLE daily_prices (date TEXT, price REAL)')
        conn.executemany('INSERT INTO daily_prices (date, price) VALUES (?, ?)', rows)
        conn.commit()
    finally:
        conn.close()


def test_repaired_pipeline_and_processor():
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is missing or is not a regular file'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable'
    assert os.path.isfile(PROCESSOR), f'{PROCESSOR} is missing or is not a regular file'

    # Execute the pipeline against the original database before checking the
    # original verifier assertion.
    content = run_pipeline()
    assert content == '101.3850', (
        f"The calculated EMA in {OUTPUT} is incorrect. Expected '101.3850', but got '{content}'."
    )

    # Exercise calculate_ema independently, including a non-default alpha, so
    # a hard-coded final output cannot substitute for repairing the formula.
    spec = importlib.util.spec_from_file_location('submitted_process_data', PROCESSOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'calculate_ema', None)), 'calculate_ema is missing or not callable'
    signature = inspect.signature(module.calculate_ema)
    assert 'alpha' in signature.parameters, 'calculate_ema must accept alpha'
    assert signature.parameters['alpha'].default == 0.1, 'The alpha default must remain 0.1'

    formula_prices = [83.25, 91.0, 77.5, 104.75, 99.125]
    for alpha in (0.1, 0.35):
        actual = module.calculate_ema(formula_prices, alpha)
        expected = expected_ema(formula_prices, alpha)
        assert abs(actual - expected) < 1e-10, (
            f'calculate_ema returned {actual} for alpha={alpha}; expected {expected}'
        )

    fd, backup = tempfile.mkstemp(prefix='data.db.backup.')
    os.close(fd)
    shutil.copy2(DATABASE, backup)
    try:
        # Rows are deliberately inserted out of date order. Running the Python
        # artifact directly validates its table name and chronological query.
        rows = [
            ('2042-05-04', 70.0),
            ('2042-05-01', 140.0),
            ('2042-05-03', 95.0),
            ('2042-05-02', 20.0),
        ]
        replace_prices(rows)
        chronological = [price for _, price in sorted(rows)]
        expected_text = f'{expected_ema(chronological):.4f}'
        result = subprocess.run(
            ['python3', PROCESSOR],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f'process_data.py failed with exit code {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert result.stdout.strip() == expected_text, (
            f'process_data.py produced {result.stdout.strip()!r}; expected {expected_text!r}'
        )

        # Exercise the complete shell pipeline on a second independently
        # derived dataset and require it to create the output file itself.
        rows = [
            ('2051-12-30', 300.5),
            ('2051-12-27', 12.25),
            ('2051-12-29', 88.0),
            ('2051-12-28', 210.75),
            ('2051-12-31', 47.125),
        ]
        replace_prices(rows)
        chronological = [price for _, price in sorted(rows)]
        expected_text = f'{expected_ema(chronological):.4f}'
        assert run_pipeline() == expected_text
    finally:
        shutil.copy2(backup, DATABASE)
        os.remove(backup)

    # Restore the requested final state and retain the original exact-content
    # assertion after actually executing the repaired artifact.
    content = run_pipeline()
    assert content == '101.3850', (
        f"The calculated EMA in {OUTPUT} is incorrect. Expected '101.3850', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
