#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import secrets
import subprocess

import h5py
import numpy as np
from scipy import stats

ANALYZE = '/home/user/analyze.py'
DATA = '/home/user/sim_data.h5'
RESULTS = '/home/user/results.txt'
PATTERN = re.compile(r'^T-statistic:\s*(-?\d+\.\d{4}),\s*P-value:\s*(\d+\.\d{4})$')


def parse_results():
    assert os.path.exists(RESULTS), f'The file {RESULTS} is missing.'
    assert os.path.isfile(RESULTS), f'{RESULTS} is not a file.'
    with open(RESULTS, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    match = PATTERN.match(content)
    assert match is not None, (
        f"The content of {RESULTS} does not match the required format. "
        f"Expected 'T-statistic: [t_val], P-value: [p_val]' with 4 decimal places. "
        f"Got: '{content}'"
    )
    return float(match.group(1)), float(match.group(2))


def run_analysis():
    if os.path.lexists(RESULTS):
        if os.path.isdir(RESULTS) and not os.path.islink(RESULTS):
            shutil.rmtree(RESULTS)
        else:
            os.unlink(RESULTS)
    completed = subprocess.run(
        ['python3', ANALYZE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'analyze.py exited with status {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    return parse_results()


def expected_for(sequences):
    decoded = [s.decode('utf-8') if isinstance(s, bytes) else str(s) for s in sequences]
    group_a = [s for s in decoded if 'GATTACA' in s]
    group_b = [s for s in decoded if 'GATTACA' not in s]
    assert group_a and group_b
    gc_a = [sum(c in 'GC' for c in s) / len(s) for s in group_a]
    gc_b = [sum(c in 'GC' for c in s) / len(s) for s in group_b]
    result = stats.ttest_ind(gc_a, gc_b, equal_var=False)
    return float(f'{result.statistic:.4f}'), float(f'{result.pvalue:.4f}')


def make_case(rng, gc_a, gc_b):
    sequences = []
    for contains_primer, gc_probability in [(True, gc_a), (False, gc_b)]:
        for _ in range(28):
            length = int(rng.integers(55, 111))
            chars = []
            for _ in range(length):
                if rng.random() < gc_probability:
                    chars.append('G' if rng.random() < 0.5 else 'C')
                else:
                    chars.append('A' if rng.random() < 0.5 else 'T')
            seq = ''.join(chars)
            if contains_primer:
                pos = int(rng.integers(0, length - 6))
                seq = seq[:pos] + 'GATTACA' + seq[pos + 7:]
            else:
                seq = seq.replace('GATTACA', 'GATTACT')
            sequences.append(seq.encode('utf-8'))
    rng.shuffle(sequences)
    return sequences


def write_dataset(sequences):
    with h5py.File(DATA, 'w') as f:
        f.create_dataset('seqs', data=np.asarray(sequences, dtype='S'))


def restore_file(path, data):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    if data is not None:
        with open(path, 'wb') as f:
            f.write(data)


def test_analysis_script_and_results():
    # Preserve the original verifier's assertions that the submitted result exists.
    assert os.path.exists(RESULTS), f'The file {RESULTS} is missing.'
    assert os.path.isfile(RESULTS), f'{RESULTS} is not a file.'

    assert os.path.exists(ANALYZE), f'The file {ANALYZE} is missing.'
    assert os.path.isfile(ANALYZE), f'{ANALYZE} is not a file.'
    assert stat.S_ISREG(os.stat(ANALYZE).st_mode), f'{ANALYZE} is not a regular file.'

    with open(DATA, 'rb') as f:
        original_data = f.read()
    with open(RESULTS, 'rb') as f:
        original_results = f.read()

    try:
        # Execute the submitted script on the supplied simulation data and retain
        # the original expected-value checks.
        t_val, p_val = run_analysis()
        expected_t = 33.3742
        expected_p = 0.0000
        assert abs(t_val - expected_t) < 0.01, (
            f'Expected T-statistic around {expected_t}, but got {t_val}.'
        )
        assert abs(p_val - expected_p) < 0.0001, (
            f'Expected P-value around {expected_p}, but got {p_val}.'
        )

        # Exercise the script on fresh hidden datasets so a hardcoded results line
        # cannot pass. Expected values are independently derived at verification.
        rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), 'big'))
        for gc_a, gc_b in [(0.52, 0.48), (0.43, 0.57)]:
            sequences = make_case(rng, gc_a, gc_b)
            expected_t, expected_p = expected_for(sequences)
            write_dataset(sequences)
            actual_t, actual_p = run_analysis()
            assert actual_t == expected_t, (
                f'Expected T-statistic {expected_t:.4f}, but got {actual_t:.4f}.'
            )
            assert actual_p == expected_p, (
                f'Expected P-value {expected_p:.4f}, but got {actual_p:.4f}.'
            )
    finally:
        restore_file(DATA, original_data)
        restore_file(RESULTS, original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
