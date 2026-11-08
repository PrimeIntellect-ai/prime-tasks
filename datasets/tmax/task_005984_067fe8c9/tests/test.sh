#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/etl_project')
EXECUTABLE = PROJECT / 'etl'
SCRIPT = PROJECT / 'tune.sh'
CSV = PROJECT / 'interactions.csv'
LOG = PROJECT / 'experiment.log'


def expected_outputs(csv_text):
    lines = csv_text.strip().splitlines()
    assert len(lines) > 1, 'CSV file is empty or missing data rows'

    global_sum = 0.0
    global_count = 0
    user_known_sum = {}
    user_known_count = {}
    missing_entries = []

    for line in lines[1:]:
        parts = line.strip().split(',')
        if len(parts) != 3:
            continue
        u, _i, r = parts
        u = int(u)
        user_known_sum.setdefault(u, 0.0)
        user_known_count.setdefault(u, 0)
        if r == '?':
            missing_entries.append(u)
        else:
            rating = float(r)
            global_sum += rating
            global_count += 1
            user_known_sum[u] += rating
            user_known_count[u] += 1

    assert global_count > 0, 'No known ratings found in CSV'
    global_avg = global_sum / global_count
    result = {}
    for alpha in [1.0, 2.0, 5.0, 10.0]:
        total = 0.0
        for u in missing_entries:
            total += (user_known_sum.get(u, 0.0) + alpha * global_avg) / (
                user_known_count.get(u, 0) + alpha
            )
        result[alpha] = f'{total:.2f}'
    return result


def test_executable_exists():
    executable_path = str(EXECUTABLE)
    assert os.path.isfile(executable_path), f'Compiled executable not found at {executable_path}'
    assert os.access(executable_path, os.X_OK), f'File {executable_path} is not executable'
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'etl must be a compiled executable'


def test_tune_script_exists():
    script_path = str(SCRIPT)
    assert os.path.isfile(script_path), f'Tuning script not found at {script_path}'


def test_experiment_log_correctness():
    log_path = str(LOG)
    csv_path = str(CSV)
    assert os.path.isfile(log_path), f'Experiment log not found at {log_path}'
    assert os.path.isfile(csv_path), f'Data file not found at {csv_path}'

    csv_text = CSV.read_text()
    expected = expected_outputs(csv_text)
    log_content = LOG.read_text().strip()

    for alpha in [1.0, 2.0, 5.0, 10.0]:
        expected_str = f'Alpha: {alpha}, Total Imputed Sum: {expected[alpha]}'
        alpha_pattern = f'Alpha:\\s*{alpha}0*\\s*,\\s*Total Imputed Sum:\\s*{expected[alpha]}'
        assert re.search(alpha_pattern, log_content), (
            f"Expected to find '{expected_str}' in {log_path}, but it was missing or incorrect.\n"
            f'Log contents:\n{log_content}'
        )


def make_random_csv():
    rng = random.SystemRandom()
    while True:
        rows = [
            'user_id,item_id,rating',
            f'1,101,{rng.randint(1,5)}',
            f'1,102,{rng.randint(1,5)}',
            '1,103,?',
            f'2,201,{rng.randint(1,5)}',
            '2,202,?',
            f'3,301,{rng.randint(1,5)}',
            '3,302,?',
            '4,401,?',
        ]
        text = '\n'.join(rows) + '\n'
        # Avoid exact half-cent ties, where language-specific rounding rules differ.
        values = expected_outputs(text)
        safe = True
        for alpha in [1.0, 2.0, 5.0, 10.0]:
            # Recompute at extra precision indirectly by perturbation is unnecessary here;
            # the finite set of generated integer datasets almost always avoids ties.
            if not re.fullmatch(r'-?\d+\.\d{2}', values[alpha]):
                safe = False
        if safe:
            return text


def run_etl(alpha, expected):
    proc = subprocess.run(
        [str(EXECUTABLE), '--alpha', str(alpha)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f'etl failed for alpha {alpha}: {proc.stderr}'
    lines = proc.stdout.splitlines()
    assert len(lines) == 1, f'etl must print exactly one line, got: {proc.stdout!r}'
    match = re.fullmatch(
        r'Alpha: ([0-9]+(?:\.[0-9]+)?), Total Imputed Sum: (-?\d+\.\d{2})',
        lines[0],
    )
    assert match, f'Incorrect etl output format: {lines[0]!r}'
    assert float(match.group(1)) == alpha, f'etl reported the wrong alpha: {lines[0]!r}'
    assert match.group(2) == expected, (
        f'Wrong imputed sum for alpha {alpha}: expected {expected}, got {match.group(2)}'
    )


def test_etl_executes_and_imputes_dynamic_data():
    original_csv = CSV.read_bytes()
    try:
        for _ in range(3):
            csv_text = make_random_csv()
            CSV.write_text(csv_text)
            expected = expected_outputs(csv_text)
            for alpha in [1.0, 2.0, 5.0, 10.0]:
                run_etl(alpha, expected[alpha])
    finally:
        CSV.write_bytes(original_csv)


def test_tune_script_actually_runs_etl_and_writes_dynamic_results(tmp_path):
    original_csv = CSV.read_bytes()
    original_log = LOG.read_bytes() if LOG.exists() else None
    saved_executable = PROJECT / '.etl.verifier-real'
    calls = tmp_path / 'etl_calls.txt'

    csv_text = make_random_csv()
    expected = expected_outputs(csv_text)

    try:
        CSV.write_text(csv_text)
        LOG.write_text('')

        os.replace(EXECUTABLE, saved_executable)
        EXECUTABLE.write_text(
            '#!/bin/bash\n'
            f'printf "%s\\n" "$*" >> {str(calls)!r}\n'
            f'exec {str(saved_executable)!r} "$@"\n'
        )
        EXECUTABLE.chmod(0o755)

        proc = subprocess.run(
            ['bash', str(SCRIPT)],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert proc.returncode == 0, f'tune.sh failed: {proc.stderr}'
        assert calls.exists(), 'tune.sh did not invoke the etl executable'
        call_lines = calls.read_text().splitlines()
        assert len(call_lines) == 4, f'tune.sh must invoke etl four times, got {call_lines}'
        for call, alpha in zip(call_lines, [1.0, 2.0, 5.0, 10.0]):
            assert re.search(rf'(^|[=\s]){re.escape(str(alpha))}($|\s)', call), (
                f'tune.sh invoked etl with the wrong alpha/order: {call_lines}'
            )

        assert LOG.is_file(), 'tune.sh did not create experiment.log'
        log_lines = LOG.read_text().splitlines()
        assert len(log_lines) == 4, f'experiment.log must contain exactly four run outputs: {log_lines}'
        for line, alpha in zip(log_lines, [1.0, 2.0, 5.0, 10.0]):
            assert line == f'Alpha: {alpha}, Total Imputed Sum: {expected[alpha]}', (
                f'Incorrect experiment output for alpha {alpha}: {line!r}'
            )
    finally:
        CSV.write_bytes(original_csv)
        if saved_executable.exists():
            os.replace(saved_executable, EXECUTABLE)
        if original_log is None:
            if LOG.exists():
                LOG.unlink()
        else:
            LOG.write_bytes(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
