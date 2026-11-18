#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import re
import shutil
import subprocess
from pathlib import Path

from scipy.special import gammainc

HOME = Path('/home/user')
REPORT = HOME / 'regression_report.json'
DATA = HOME / 'snp_counts.csv'
REFERENCE = HOME / 'reference.txt'


def load_report(path):
    assert path.exists(), f'File {path} does not exist.'
    try:
        with path.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        assert False, f'File {path} does not contain valid JSON.'


def check_original_report(data):
    assert 'computed_mean' in data, "Missing 'computed_mean' in JSON."
    assert 'reference_mean' in data, "Missing 'reference_mean' in JSON."
    assert 'status' in data, "Missing 'status' in JSON."
    assert data['reference_mean'] == 2.62, \
        f"Reference mean is {data['reference_mean']}, expected 2.62."
    computed = data['computed_mean']
    assert isinstance(computed, (int, float)), "'computed_mean' must be a number."
    assert abs(computed - 2.62) <= 0.05, \
        f'Computed mean {computed} is out of expected bounds (2.62 +/- 0.05).'
    assert computed == round(computed, 2), \
        f'Computed mean {computed} should be rounded to exactly 2 decimal places.'
    assert data['status'] == 'PASS', \
        f"Status should be 'PASS', but got '{data['status']}'."


def posterior_mean(rows):
    total_t = sum(t for t, _ in rows)
    total_y = sum(y for _, y in rows)
    # Posterior is a Gamma(total_y + 1, rate=total_t), truncated to [0, 10].
    shape = total_y + 1
    return (shape / total_t) * (
        gammainc(shape + 1, 10.0 * total_t) /
        gammainc(shape, 10.0 * total_t)
    )


def write_case(rows, reference):
    DATA.write_text(
        'exposure_time,snp_count\n' +
        ''.join(f'{t},{y}\n' for t, y in rows)
    )
    REFERENCE.write_text(f'{reference}\n')
    if REPORT.exists():
        REPORT.unlink()


def check_challenge_report(rows, reference):
    data = load_report(REPORT)
    assert 'computed_mean' in data, "Missing 'computed_mean' in JSON."
    assert 'reference_mean' in data, "Missing 'reference_mean' in JSON."
    assert 'status' in data, "Missing 'status' in JSON."
    assert data['reference_mean'] == reference, \
        'The report did not preserve the exact value read from reference.txt.'
    computed = data['computed_mean']
    assert isinstance(computed, (int, float)) and not isinstance(computed, bool), \
        "'computed_mean' must be a number."
    assert math.isfinite(computed), "'computed_mean' must be finite."
    assert computed == round(computed, 2), \
        f'Computed mean {computed} should be rounded to exactly 2 decimal places.'
    expected = posterior_mean(rows)
    assert abs(computed - expected) <= 0.05, \
        f'Computed mean {computed} is inconsistent with the supplied SNP data.'
    expected_status = 'PASS' if abs(computed - reference) <= 0.05 else 'FAIL'
    assert data['status'] == expected_status, \
        f"Status should be '{expected_status}', but got '{data['status']}'."


def source_files_and_commands():
    excluded = {DATA.resolve(), REFERENCE.resolve(), REPORT.resolve()}
    sources = []
    commands = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.resolve() in excluded:
            continue
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        if len(raw) > 1_000_000 or b'\x00' in raw:
            continue
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue

        suffix = path.suffix.lower()
        first = text.splitlines()[0] if text.splitlines() else ''
        is_source = suffix in {'.py', '.sh', '.bash', '.pl', '.rb', '.js'} or first.startswith('#!')
        if not is_source:
            continue
        sources.append(text)

        if suffix == '.py' or 'python' in first:
            commands.append(['python3', str(path)])
        elif suffix in {'.sh', '.bash'} or re.search(r'\b(?:ba)?sh\b', first):
            commands.append(['bash', str(path)])
        elif suffix == '.pl' or 'perl' in first:
            if shutil.which('perl'):
                commands.append(['perl', str(path)])
        elif suffix == '.rb' or 'ruby' in first:
            if shutil.which('ruby'):
                commands.append(['ruby', str(path)])
        elif suffix == '.js' or 'node' in first:
            if shutil.which('node'):
                commands.append(['node', str(path)])
        elif os.access(path, os.X_OK):
            commands.append([str(path)])
    return sources, commands


def inspect_mcmc_source(sources):
    assert sources, 'No sampler script was found under /home/user.'
    corpus = '\n'.join(sources).lower()
    compact = corpus.replace('_', '').replace(',', '')
    assert '50000' in compact, 'Sampler source does not specify 50,000 iterations.'
    assert '10000' in compact, 'Sampler source does not specify the 10,000-sample burn-in.'
    assert re.search(r'(?<!\d)42(?!\d)', corpus), 'Sampler source does not set seed 42.'
    assert re.search(r'(?<!\d)(?:0?\.5|5e-1)(?!\d)', corpus), \
        'Sampler source does not specify proposal standard deviation 0.5.'
    assert re.search(r'\b(for|while)\b', corpus), 'No sampling loop was found.'
    assert re.search(r'normal|gauss', corpus), 'No Normal proposal draw was found.'
    assert re.search(r'accept|ratio|alpha', corpus), 'No Metropolis-Hastings acceptance calculation was found.'
    assert re.search(r'sample|chain', corpus), 'No MCMC sample chain was found.'
    assert not re.search(r'\b(?:import|from)\s+(?:pymc|stan|cmdstanpy|emcee)\b', corpus), \
        'An external MCMC library is not permitted.'


def main():
    original_data = DATA.read_bytes()
    original_reference = REFERENCE.read_bytes()
    original_report = REPORT.read_bytes() if REPORT.exists() else None

    # Preserve every assertion made by the original verifier.
    check_original_report(load_report(REPORT))

    sources, commands = source_files_and_commands()
    inspect_mcmc_source(sources)
    assert commands, 'No runnable sampler script was found under /home/user.'

    cases = [
        ([(0.7, 1), (1.3, 4), (2.1, 5), (0.9, 2), (1.5, 3)], 2.46),
        ([(1.2, 4), (0.8, 2), (2.5, 8), (1.7, 5), (0.6, 1)], 3.14),
    ]

    passed = False
    try:
        for command in commands:
            candidate_ok = True
            for rows, reference in cases:
                write_case(rows, reference)
                try:
                    subprocess.run(
                        command,
                        cwd=str(HOME),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=30,
                        check=False,
                        env=os.environ.copy(),
                    )
                    check_challenge_report(rows, reference)
                except (AssertionError, OSError, subprocess.TimeoutExpired):
                    candidate_ok = False
                    break
            if candidate_ok:
                passed = True
                break
        assert passed, 'No submitted script produced correct reports when executed on verifier-supplied SNP data.'
    finally:
        DATA.write_bytes(original_data)
        REFERENCE.write_bytes(original_reference)
        if original_report is None:
            if REPORT.exists():
                REPORT.unlink()
        else:
            REPORT.write_bytes(original_report)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
