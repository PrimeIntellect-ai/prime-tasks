#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import shutil
import signal
import subprocess
import uuid

import pytest

SCRIPT = '/home/user/analyze_logs.sh'
RAW = '/home/user/raw_logs'
PROCESSED = '/home/user/processed'


def run_script(timeout=20):
    proc = subprocess.Popen(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f'Script timed out. stdout={stdout!r}, stderr={stderr!r}')
    assert proc.returncode == 0, (
        f'Script exited with status {proc.returncode}. '
        f'stdout={stdout!r}, stderr={stderr!r}'
    )


def expected_csv(valid_records):
    hourly = {}
    for ts, mutations in valid_records:
        hour = ts // 3600
        hourly[hour] = hourly.get(hour, 0) + mutations
    low, high = min(hourly), max(hourly)
    rows = []
    for hour in range(low, high + 1):
        current = hourly.get(hour, 0)
        rolling = sum(hourly.get(h, 0) for h in range(hour - 2, hour + 1))
        rows.append(f'{hour},{current},{rolling}')
    return rows


@pytest.fixture(scope='session', autouse=True)
def exercise_script_on_unseen_inputs():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'

    with open(SCRIPT, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ''
    assert first_line.startswith('#!') and 'bash' in first_line, \
        'analyze_logs.sh must be an executable Bash script.'
    assert not re.search(r'\b(?:python(?:[0-9.]+)?|perl)\b', source, re.I), \
        'The submitted script may not invoke Python or Perl.'

    executable_source = '\n'.join(
        line for line in source.splitlines() if not line.lstrip().startswith('#')
    )
    background_job = re.search(r'(?<![&>])&(?![&])', executable_source)
    xargs_parallel = re.search(
        r'\bxargs\b[\s\S]{0,300}(?:-P(?:\s*[^\s]+)?|--max-procs(?:=|\s+)[^\s]+)',
        executable_source,
    )
    assert background_job or xargs_parallel, \
        'The script must process input files in parallel using background jobs or xargs -P.'

    token = uuid.uuid4().hex
    raw_backup = f'{RAW}.verifier-backup-{token}'
    processed_backup = f'{PROCESSED}.verifier-backup-{token}'
    os.rename(RAW, raw_backup)
    os.rename(PROCESSED, processed_backup)
    os.makedirs(RAW)
    os.makedirs(PROCESSED)

    rng = random.SystemRandom()
    datasets = []
    try:
        for offsets in ([0, 0, 2, 4], [0, 1, 1, 3], [0, 3, 5]):
            name = f'unseen_{uuid.uuid4().hex}'
            base_hour = rng.randrange(100, 50000)
            valid = []
            lines = []
            for index, offset in enumerate(offsets):
                ts = (base_hour + offset) * 3600 + rng.randrange(0, 3600)
                mutations = rng.randrange(1, 50)
                valid.append((ts, mutations))
                # Vary field order and include irrelevant fields.
                if index % 2:
                    obj = {'mutations': mutations, 'extra': token, 'ts': ts}
                else:
                    obj = {'ts': ts, 'mutations': mutations, 'extra': index}
                lines.append(json.dumps(obj, separators=(',', ':')))

            bad_ts = (base_hour + rng.randrange(0, 6)) * 3600
            bad_mutations = rng.randrange(1000, 5000)
            lines.insert(
                rng.randrange(0, len(lines) + 1),
                '{"ts":%d,"mutations":%d,"info":"broken \\uZZZZ value"}'
                % (bad_ts, bad_mutations),
            )
            path = os.path.join(RAW, name + '.jsonl')
            with open(path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines) + '\n')
            datasets.append((name, valid))

        run_script()

        actual_csvs = sorted(os.path.basename(p) for p in glob.glob(PROCESSED + '/*.csv'))
        expected_names = sorted(name + '.csv' for name, _ in datasets)
        assert actual_csvs == expected_names, (
            f'Expected exactly {expected_names}, got {actual_csvs}'
        )

        for name, valid in datasets:
            output = os.path.join(PROCESSED, name + '.csv')
            assert os.path.isfile(output), f'Output file {output} does not exist.'
            with open(output, 'r', encoding='utf-8') as f:
                content = f.read().strip().splitlines()
            assert content == expected_csv(valid), (
                f'Incorrect output for unseen input {name}: {content}'
            )
    finally:
        shutil.rmtree(RAW, ignore_errors=True)
        shutil.rmtree(PROCESSED, ignore_errors=True)
        os.rename(raw_backup, RAW)
        os.rename(processed_backup, PROCESSED)

    # Discard all pre-existing CSV answers and execute the script on the original data.
    for path in glob.glob(PROCESSED + '/*.csv'):
        os.remove(path)
    run_script()


def test_script_exists_and_executable():
    script_path = '/home/user/analyze_logs.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_processed_files_exist():
    alpha_csv = '/home/user/processed/server_alpha.csv'
    beta_csv = '/home/user/processed/server_beta.csv'

    assert os.path.isfile(alpha_csv), f"Output file {alpha_csv} does not exist."
    assert os.path.isfile(beta_csv), f"Output file {beta_csv} does not exist."


def test_server_alpha_output():
    alpha_csv = '/home/user/processed/server_alpha.csv'
    expected_lines = [
        "1,2,2",
        "2,5,7",
        "3,0,7",
        "4,3,8"
    ]

    with open(alpha_csv, 'r') as f:
        content = f.read().strip().split('\n')

    assert content == expected_lines, f"Content of {alpha_csv} does not match expected output. Got: {content}"


def test_server_beta_output():
    beta_csv = '/home/user/processed/server_beta.csv'
    expected_lines = [
        "10,10,10",
        "11,5,15"
    ]

    with open(beta_csv, 'r') as f:
        content = f.read().strip().split('\n')

    assert content == expected_lines, f"Content of {beta_csv} does not match expected output. Got: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
