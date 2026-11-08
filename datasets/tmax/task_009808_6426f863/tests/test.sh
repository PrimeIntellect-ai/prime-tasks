#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess

USERS = '/home/user/users.csv'
TRANSACTIONS = '/home/user/transactions.csv'
SOURCE = '/home/user/bootstrap.c'
EXECUTABLE = '/home/user/bootstrap'
CI = '/home/user/ci.txt'


def expected_ci(users_file, transactions_file):
    users = {}
    with open(users_file, 'r') as f:
        for row in csv.DictReader(f):
            users[row['user_id']] = row['group']

    data = []
    with open(transactions_file, 'r') as f:
        for row in csv.DictReader(f):
            uid = row['user_id']
            if uid in users:
                data.append((int(uid), users[uid], float(row['amount'])))

    data.sort(key=lambda x: x[0])
    data = [(x[1], x[2]) for x in data]
    N = len(data)
    assert N > 0

    state = 42

    def xorshift32():
        nonlocal state
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= (state >> 17) & 0xFFFFFFFF
        state ^= (state << 5) & 0xFFFFFFFF
        return state

    diffs = []
    for _ in range(10000):
        indices = [xorshift32() % N for _ in range(N)]
        sample = [data[i] for i in indices]
        amounts = [x[1] for x in sample]
        mean_amt = sum(amounts) / N
        var_amt = sum((x - mean_amt) ** 2 for x in amounts) / N
        std_amt = math.sqrt(var_amt)
        if std_amt == 0:
            std_amt = 1e-9

        sum_A = count_A = 0
        sum_B = count_B = 0
        for grp, amt in sample:
            z = (amt - mean_amt) / std_amt
            if grp == 'A':
                sum_A += z
                count_A += 1
            else:
                sum_B += z
                count_B += 1

        mean_z_A = sum_A / count_A if count_A else 0.0
        mean_z_B = sum_B / count_B if count_B else 0.0
        diffs.append(mean_z_B - mean_z_A)

    diffs.sort()
    return f'{diffs[250]:.4f},{diffs[9749]:.4f}'


def run_program():
    subprocess.run([EXECUTABLE], cwd='/home/user', check=True, timeout=20)
    assert os.path.exists(CI), f'Missing {CI} - did your C program generate it?'
    with open(CI, 'r') as f:
        return f.read().strip()


def test_compiled_c_pipeline_and_ci_content():
    # Preserve the original verifier's file and exact-result assertions.
    assert os.path.exists(USERS), f'Missing {USERS}'
    assert os.path.exists(TRANSACTIONS), f'Missing {TRANSACTIONS}'
    assert os.path.exists(CI), f'Missing {CI} - did your C program run and generate it?'

    assert os.path.lexists(SOURCE), f'Missing required C source file {SOURCE}'
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f'{SOURCE} must be a regular C source file'

    original_users = open(USERS, 'rb').read()
    original_transactions = open(TRANSACTIONS, 'rb').read()
    original_expected = expected_ci(USERS, TRANSACTIONS)

    if os.path.lexists(EXECUTABLE):
        os.unlink(EXECUTABLE)

    compile_result = subprocess.run(
        ['gcc', '-O2', '-std=c11', SOURCE, '-lm', '-o', EXECUTABLE],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert compile_result.returncode == 0, 'bootstrap.c did not compile:\n' + compile_result.stdout
    assert stat.S_ISREG(os.lstat(EXECUTABLE).st_mode), f'{EXECUTABLE} must be a regular executable'
    assert os.access(EXECUTABLE, os.X_OK), f'{EXECUTABLE} is not executable'

    actual = run_program()
    assert actual == original_expected, (
        f'The contents of {CI} do not match the expected values.\n'
        f"Expected: '{original_expected}'\nActual:   '{actual}'\n"
        'Ensure you use the custom PRNG, standardize within each bootstrap sample, '
        'and format the output exactly as requested.'
    )

    # Exercise the freshly compiled artifact on unpredictable input so a program
    # that merely writes the fixed original answer cannot pass.
    try:
        while True:
            amounts = [10.0 + secrets.randbelow(9000) / 10.0 for _ in range(10)]
            groups = ['A', 'B', 'B', 'A', 'A', 'B', 'A', 'B', 'A', 'B']
            with open(USERS, 'w', newline='') as f:
                f.write('user_id,group\n')
                for uid, group in enumerate(groups, 1):
                    f.write(f'{uid},{group}\n')
            with open(TRANSACTIONS, 'w', newline='') as f:
                f.write('user_id,amount\n')
                for uid, amount in enumerate(amounts, 1):
                    f.write(f'{uid},{amount:.1f}\n')
            dynamic_expected = expected_ci(USERS, TRANSACTIONS)
            if dynamic_expected != original_expected:
                break

        if os.path.exists(CI):
            os.unlink(CI)
        dynamic_actual = run_program()
        assert dynamic_actual == dynamic_expected, (
            'The compiled bootstrap executable did not recompute the CI for changed input.\n'
            f"Expected: '{dynamic_expected}'\nActual:   '{dynamic_actual}'"
        )
    finally:
        with open(USERS, 'wb') as f:
            f.write(original_users)
        with open(TRANSACTIONS, 'wb') as f:
            f.write(original_transactions)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
