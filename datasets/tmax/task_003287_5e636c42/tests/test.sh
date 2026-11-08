#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shlex
import stat
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

PREPROCESS = Path('/home/user/preprocess.py')
PIPELINE = Path('/home/user/evaluate_pipeline.sh')
RAW = Path('/home/user/raw_data.csv')
PROCESSED = Path('/home/user/processed_data.csv')
LOG_PATHS = [
    Path('/home/user/reproducibility.log'),
    Path('/home/user/accuracy.log'),
    Path('/home/user/benchmark.log'),
]


def clean_outputs():
    for path in LOG_PATHS + [PROCESSED]:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_pipeline():
    result = subprocess.run([str(PIPELINE)], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f'{PIPELINE} failed with return code {result.returncode}.\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    return result


@pytest.fixture(scope='module', autouse=True)
def run_and_validate_pipeline():
    """Validate preprocessing behavior and exercise the evaluation decisions."""
    assert PREPROCESS.exists(), f'{PREPROCESS} does not exist.'
    assert PREPROCESS.is_file(), f'{PREPROCESS} is not a regular file.'
    assert PIPELINE.exists(), f'{PIPELINE} does not exist.'
    assert PIPELINE.is_file(), f'{PIPELINE} is not a regular file.'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable.'

    original_preprocess = PREPROCESS.read_bytes()
    original_mode = stat.S_IMODE(PREPROCESS.stat().st_mode)
    original_raw = RAW.read_bytes()
    time_path = Path('/usr/bin/time')
    saved_time = Path(f'/tmp/verifier-real-time-{os.getpid()}')
    time_replaced = False

    def restore_preprocess():
        PREPROCESS.write_bytes(original_preprocess)
        os.chmod(PREPROCESS, original_mode)

    def install_probe(source):
        PREPROCESS.write_text(source)
        os.chmod(PREPROCESS, 0o755)

    try:
        # Execute the submitted preprocessor on verifier-selected data and derive
        # the expected sample-standardized values independently.
        source = pd.DataFrame({
            'f1': [1.0, 2.0, 4.0, 8.0, 16.0],
            'f2': [-3.0, 0.0, 5.0, 9.0, 10.0],
            'f3': [100.0, 90.0, 70.0, 40.0, 0.0],
        })
        source.to_csv(RAW, index=False)
        clean_outputs()
        result = subprocess.run(
            ['python3', str(PREPROCESS)], capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f'{PREPROCESS} failed on controlled input.\n'
            f'stdout: {result.stdout}\nstderr: {result.stderr}'
        )
        assert PROCESSED.exists(), f'{PREPROCESS} did not create {PROCESSED}.'

        with PROCESSED.open(newline='') as f:
            rows = list(csv.reader(f))
        assert rows[0] == ['f1', 'f2', 'f3'], 'Processed CSV header is incorrect.'
        assert len(rows) == len(source) + 1, 'Processed CSV has the wrong row count.'
        assert all(len(row) == 3 for row in rows[1:]), 'Processed CSV has extra or missing columns.'
        decimal = re.compile(r'^-?(?:0|[1-9][0-9]*)\.[0-9]{6}$')
        assert all(decimal.fullmatch(value) for row in rows[1:] for value in row), (
            'Every processed value must be written with exactly 6 decimal places.'
        )

        actual = np.array([[float(value) for value in row] for row in rows[1:]])
        values = source.to_numpy(dtype=float)
        expected = (values - values.mean(axis=0)) / values.std(axis=0, ddof=1)
        np.testing.assert_allclose(actual, expected, rtol=0, atol=5.1e-7)

        # Restore the supplied input before testing the evaluation script.
        RAW.write_bytes(original_raw)

        # A deterministic but numerically invalid preprocessor must be run three
        # times and must cause the evaluation's accuracy check to reject output.
        bad_counter = Path(f'/tmp/preprocess-bad-count-{os.getpid()}')
        bad_counter.unlink(missing_ok=True)
        install_probe(f'''#!/usr/bin/env python3
from pathlib import Path
import pandas as pd
counter = Path({str(bad_counter)!r})
with counter.open('a') as f:
    f.write('run\\n')
pd.DataFrame({{'f1': [7.0, 7.0, 7.0], 'f2': [2.0, 2.0, 2.0], 'f3': [9.0, 9.0, 9.0]}}).to_csv('/home/user/processed_data.csv', index=False, float_format='%.6f')
''')
        clean_outputs()
        run_pipeline()
        assert bad_counter.exists() and len(bad_counter.read_text().splitlines()) >= 3, (
            'The evaluation script did not run preprocess.py for both reproducibility runs and the benchmark.'
        )
        assert Path('/home/user/accuracy.log').read_text().strip() == 'INACCURATE', (
            'The accuracy test did not reject non-standardized output.'
        )

        # Changing output on every invocation must be detected as divergent.
        divergent_counter = Path(f'/tmp/preprocess-divergent-count-{os.getpid()}')
        divergent_counter.unlink(missing_ok=True)
        install_probe(f'''#!/usr/bin/env python3
from pathlib import Path
import pandas as pd
counter = Path({str(divergent_counter)!r})
try:
    n = int(counter.read_text()) + 1
except (FileNotFoundError, ValueError):
    n = 1
counter.write_text(str(n))
pd.DataFrame({{'f1': [n, n, n], 'f2': [n + 1, n + 1, n + 1], 'f3': [n + 2, n + 2, n + 2]}}).to_csv('/home/user/processed_data.csv', index=False, float_format='%.6f')
''')
        clean_outputs()
        run_pipeline()
        assert int(divergent_counter.read_text()) >= 3, (
            'The evaluation script did not execute all required preprocessing runs.'
        )
        assert Path('/home/user/reproducibility.log').read_text().strip() == 'DIVERGENT', (
            'The reproducibility test did not detect differing outputs.'
        )

        # Run the submitted implementation normally. Instrument /usr/bin/time
        # to establish that the required absolute command is genuinely invoked.
        restore_preprocess()
        RAW.write_bytes(original_raw)
        time_marker = Path(f'/tmp/time-invocation-{os.getpid()}')
        time_marker.unlink(missing_ok=True)
        os.rename(time_path, saved_time)
        time_replaced = True
        time_path.write_text(
            '#!/bin/sh\n'
            f'printf "%s\\n" "$*" >> {shlex.quote(str(time_marker))}\n'
            f'exec {shlex.quote(str(saved_time))} "$@"\n'
        )
        os.chmod(time_path, 0o755)

        clean_outputs()
        run_pipeline()
        assert time_marker.exists(), 'The pipeline did not invoke /usr/bin/time.'
        invocations = time_marker.read_text().splitlines()
        assert any(line.startswith('-p ') and '/home/user/preprocess.py' in line for line in invocations), (
            'The benchmark did not use /usr/bin/time -p to execute preprocess.py.'
        )
    finally:
        restore_preprocess()
        RAW.write_bytes(original_raw)
        if time_replaced:
            try:
                time_path.unlink()
            except FileNotFoundError:
                pass
            os.rename(saved_time, time_path)


def test_reproducibility_log():
    path = '/home/user/reproducibility.log'
    assert os.path.exists(path), f'File {path} is missing. The bash script did not create it.'
    with open(path, 'r') as f:
        content = f.read()
    assert content.strip() == 'REPRODUCIBLE', f"Expected 'REPRODUCIBLE' in {path}, got '{content.strip()}'"


def test_accuracy_log():
    path = '/home/user/accuracy.log'
    assert os.path.exists(path), f'File {path} is missing. The bash script did not create it.'
    with open(path, 'r') as f:
        content = f.read()
    assert content.strip() == 'ACCURATE', f"Expected 'ACCURATE' in {path}, got '{content.strip()}'"


def test_benchmark_log():
    path = '/home/user/benchmark.log'
    assert os.path.exists(path), f'File {path} is missing. The bash script did not create it.'
    with open(path, 'r') as f:
        content = f.read()
    assert re.search(r'^real\s+[0-9\.]+', content, re.MULTILINE), f"{path} is missing 'real' time output from /usr/bin/time -p."
    assert re.search(r'^user\s+[0-9\.]+', content, re.MULTILINE), f"{path} is missing 'user' time output from /usr/bin/time -p."
    assert re.search(r'^sys\s+[0-9\.]+', content, re.MULTILINE), f"{path} is missing 'sys' time output from /usr/bin/time -p."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
