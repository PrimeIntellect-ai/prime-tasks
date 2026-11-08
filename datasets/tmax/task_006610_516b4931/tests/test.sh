#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import hashlib
import os
import random
import re
import subprocess
from collections import Counter
from pathlib import Path

import pandas as pd

HOME = Path('/home/user')
RAW = HOME / 'raw_survey.csv'
OUTPUTS = [HOME / n for n in ('cleaned.csv', 'reshaped.csv', 'anonymized.csv', 'final_sample.csv')]

CANONICAL = '''id,name,email,department,q1,q2,q3,feedback
1,Alice,ALICE@test.com,HR,5.0,4.0,,Great job!
2,Bob,bob@test.com,ENG,,3.0,2.0,"This feedback
has an embedded newline"
3,Charlie,charlie@test.com,HR,1.0,2.0,3.0,Okay
4,David,david@test.com,ENG,4.0,,5.0,Excellent
5,Eve,eve@test.com,ENG,5.0,5.0,4.0,Good
6,Frank,frank@test.com,HR,3.0,3.0,3.0,Fair
7,Grace,grace@test.com,ENG,2.0,1.0,,Needs work
8,Heidi,heidi@test.com,HR,4.0,5.0,5.0,Awesome
9,Ivan,ivan@test.com,ENG,1.0,,1.0,"Another
newline"
10,Judy,judy@test.com,ENG,5.0,4.0,4.0,Perfect
'''


def run_make(*args):
    result = subprocess.run(
        ['make', *args], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"make {' '.join(args)} failed:\n{result.stdout}"
    return result.stdout


def remove_outputs():
    for path in OUTPUTS:
        if path.exists() or path.is_symlink():
            path.unlink()


def norm(value):
    if pd.isna(value):
        return ('NA',)
    if isinstance(value, float):
        return ('NUM', round(value, 10))
    return ('VAL', str(value))


def rows(df, columns):
    return Counter(tuple(norm(row[c]) for c in columns) for _, row in df.iterrows())


def assert_same(actual, expected, label):
    assert list(actual.columns) == list(expected.columns), (
        f"{label} columns differ: expected {list(expected.columns)}, got {list(actual.columns)}"
    )
    assert len(actual) == len(expected), (
        f"{label} row count differs: expected {len(expected)}, got {len(actual)}"
    )
    assert rows(actual, expected.columns) == rows(expected, expected.columns), (
        f"{label} contents do not match the required transformation"
    )


def expected_frames():
    raw = pd.read_csv(RAW)
    bad = raw['feedback'].astype(str).str.contains(r'[\r\n]', regex=True, na=False)
    cleaned = raw.loc[~bad].copy().reset_index(drop=True)

    id_vars = [c for c in cleaned.columns if c not in ('q1', 'q2', 'q3')]
    reshaped = cleaned.melt(
        id_vars=id_vars, value_vars=['q1', 'q2', 'q3'],
        var_name='question', value_name='score'
    )
    reshaped['score'] = pd.to_numeric(reshaped['score'], errors='coerce')
    mean = reshaped['score'].mean()
    reshaped.loc[reshaped['score'].isna(), 'score'] = round(float(mean), 1)

    anonymized = reshaped.copy()
    anonymized['name'] = 'REDACTED'
    anonymized['email'] = anonymized['email'].map(
        lambda x: hashlib.sha256(str(x).lower().encode('utf-8')).hexdigest()
    )
    return cleaned, reshaped, anonymized


def sample_candidates(anonymized):
    candidates = []
    for sort in (True, False):
        candidates.append(
            anonymized.groupby('department', group_keys=False, sort=sort).sample(
                frac=0.5, random_state=42
            )
        )
        groups = anonymized.groupby('department', sort=sort)
        candidates.append(pd.concat([
            group.sample(frac=0.5, random_state=42) for _, group in groups
        ]))
    return candidates


def read_output(path):
    assert path.exists(), f"{path} does not exist"
    assert path.is_file(), f"{path} is not a regular file"
    return pd.read_csv(path)


def verify_outputs(canonical=False):
    cleaned_exp, reshaped_exp, anonymized_exp = expected_frames()
    cleaned = read_output(OUTPUTS[0])
    reshaped = read_output(OUTPUTS[1])
    anonymized = read_output(OUTPUTS[2])
    final = read_output(OUTPUTS[3])

    assert_same(cleaned, cleaned_exp, 'cleaned.csv')
    assert_same(reshaped, reshaped_exp, 'reshaped.csv')
    assert_same(anonymized, anonymized_exp, 'anonymized.csv')

    assert list(final.columns) == list(anonymized_exp.columns), 'final_sample.csv has wrong columns'
    expected_sizes = anonymized_exp.groupby('department').size().map(lambda n: round(n * 0.5))
    actual_sizes = final.groupby('department').size()
    assert actual_sizes.to_dict() == expected_sizes.to_dict(), 'final sample is not 50% per department'
    assert any(
        rows(final, final.columns) == rows(candidate, candidate.columns)
        for candidate in sample_candidates(anonymized_exp)
    ), 'final_sample.csv is not the reproducible random_state=42 stratified sample'

    if canonical:
        # Preserve the original verifier's assertions on the supplied input.
        assert len(cleaned) == 8, f"Expected 8 rows in cleaned.csv, got {len(cleaned)}"
        ids = {str(x) for x in cleaned['id']}
        assert '2' not in ids and '9' not in ids
        assert ids == {'1', '3', '4', '5', '6', '7', '8', '10'}

        assert len(reshaped) == 24
        assert 'question' in reshaped.columns and 'score' in reshaped.columns
        assert any(abs(float(x) - 3.7) < 1e-9 for x in reshaped['score'])

        assert len(anonymized) == 24
        assert (anonymized['name'] == 'REDACTED').all()
        alice_hash = hashlib.sha256(b'alice@test.com').hexdigest()
        assert alice_hash in set(anonymized['email'])

        assert len(final) == 12
        counts = final['department'].value_counts().to_dict()
        assert counts.get('HR', 0) == 6 and counts.get('ENG', 0) == 6
        assert (final['name'] == 'REDACTED').all()
        assert any(abs(float(x) - 3.7) < 1e-9 for x in final['score'])


def exercise(fixture, canonical=False):
    RAW.write_text(fixture, encoding='utf-8')
    remove_outputs()
    run_make('all')
    verify_outputs(canonical=canonical)

    first = OUTPUTS[3].read_bytes()
    OUTPUTS[3].unlink()
    run_make('all')
    assert OUTPUTS[3].read_bytes() == first, 'sample target is not reproducible'
    verify_outputs(canonical=canonical)


def dynamic_fixture():
    rng = random.SystemRandom()
    base = rng.randrange(10000, 90000)
    lines = ['id,name,email,department,q1,q2,q3,feedback']
    departments = ['OPS', 'SALES']
    for d_index, department in enumerate(departments):
        for i in range(5):
            ident = base + d_index * 100 + i
            name = f'Person{ident}'
            email = f'USER{ident}@Example.COM'
            vals = [str(rng.randrange(1, 10)), str(rng.randrange(1, 10)), str(rng.randrange(1, 10))]
            if i == 1:
                vals[(d_index + i) % 3] = ''
            if i == 4:
                feedback = '"generated feedback\nwith embedded newline"'
            else:
                feedback = f'feedback-{ident}'
            lines.append(','.join([str(ident), name, email, department, *vals, feedback]))
    return '\n'.join(lines) + '\n'


def main():
    makefile = HOME / 'Makefile'
    assert makefile.exists() and makefile.is_file(), '/home/user/Makefile does not exist or is not a file'

    for target in ('clean', 'reshape', 'anonymize', 'sample', 'all'):
        run_make('-n', target)

    dry_run = run_make('-B', '-n', 'all')
    py_files = list(HOME.glob('*.py'))
    assert py_files, 'No Python pipeline scripts were created in /home/user'
    assert any(re.search(r'(^|[\s/])' + re.escape(p.name) + r'([\s;]|$)', dry_run) for p in py_files), (
        'make all does not execute a Python pipeline script'
    )

    # A generated input prevents fixed, fabricated CSV deliverables from passing.
    exercise(dynamic_fixture(), canonical=False)
    # Re-run on the task's supplied input and retain all original assertions.
    exercise(CANONICAL, canonical=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
