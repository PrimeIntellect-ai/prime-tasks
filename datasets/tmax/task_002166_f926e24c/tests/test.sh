#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
from pathlib import Path

HOME = Path('/home/user')
USERS = HOME / 'users.csv'
PURCHASES = HOME / 'purchases.csv'
PRODUCTS = HOME / 'products.csv'
OUTPUT = HOME / 'recommendation.txt'

ORIGINAL = {
    'users.csv': '''user_id,name
1,Alice
2,Bob
3,Charlie
4,David
5,Eve
''',
    'products.csv': '''product_id,category
100,Electronics
101,Electronics
102,Books
103,Books
104,Clothing
''',
    'purchases.csv': '''user_id,product_id
1,100
1,101
2,100
2,101
2,102
3,101
3,103
4,104
''',
}

TIE_CASE = {
    'users.csv': '''user_id,name
1,Target
2,LowerTie
3,HigherTie
4,NoPurchases
''',
    'products.csv': '''product_id,category
10,A
11,A
12,B
13,B
''',
    'purchases.csv': '''user_id,product_id
1,10
1,11
2,10
2,12
3,11
3,13
''',
}

LARGE_INTEGER_CASE = {
    'users.csv': '''user_id,name
1,Target
2,Neighbor
3,Other
4,NoPurchases
''',
    'products.csv': '''product_id,category
9007199254740993,A
9007199254740995,B
9007199254740997,C
''',
    'purchases.csv': '''user_id,product_id
1,9007199254740993
2,9007199254740993
2,9007199254740995
3,9007199254740997
''',
}


def write_case(case):
    for name, content in case.items():
        (HOME / name).write_text(content)


def expected_from_current_data():
    with USERS.open(newline='') as f:
        registered = {int(row['user_id']) for row in csv.DictReader(f)}
    with PRODUCTS.open(newline='') as f:
        valid_products = {int(row['product_id']) for row in csv.DictReader(f)}

    bought = {}
    with PURCHASES.open(newline='') as f:
        for row in csv.DictReader(f):
            user_id = int(row['user_id'])
            product_id = int(row['product_id'])
            if user_id in registered and product_id in valid_products:
                bought.setdefault(user_id, set()).add(product_id)

    target = bought[1]
    similarities = []
    for user_id, products in bought.items():
        if user_id == 1:
            continue
        union = target | products
        similarity = len(target & products) / len(union)
        similarities.append((similarity, user_id))

    best_similarity = max(score for score, _ in similarities)
    best_user = min(user_id for score, user_id in similarities if score == best_similarity)
    return min(bought[best_user] - target)


def run_case(script, case, require_original=False):
    write_case(case)
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    result = subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{script} exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist after running {script}.'

    content = OUTPUT.read_text().strip()
    expected = str(expected_from_current_data())
    assert content == expected, f"Expected recommendation '{expected}', but found '{content}' in {OUTPUT}."
    if require_original:
        # Preserve the original verifier's exact assertion.
        assert content == '102', f"Expected recommendation '102', but found '{content}' in {OUTPUT}."


def test_recommendation_pipeline_script():
    scripts = sorted(
        path for path in HOME.rglob('*.py')
        if path.is_file() and '__pycache__' not in path.parts
    )
    assert scripts, 'No Python script was created under /home/user.'

    failures = []
    successful = None
    try:
        for script in scripts:
            try:
                run_case(script, ORIGINAL, require_original=True)
                run_case(script, TIE_CASE)
                run_case(script, LARGE_INTEGER_CASE)
                # Leave the successful pipeline validated against the original data too.
                run_case(script, ORIGINAL, require_original=True)
                successful = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert successful is not None, (
            'No Python script correctly implemented the recommendation pipeline:\n'
            + '\n'.join(failures)
        )
    finally:
        write_case(ORIGINAL)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
