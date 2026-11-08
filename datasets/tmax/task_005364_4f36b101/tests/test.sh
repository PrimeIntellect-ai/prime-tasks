#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import stat
import subprocess
from collections import defaultdict
from pathlib import Path

ACCOUNTS = Path('/home/user/accounts.csv')
TRANSACTIONS = Path('/home/user/transactions.csv')
SOURCE = Path('/home/user/find_cycles.cpp')
BINARY = Path('/home/user/find_cycles')
LOG = Path('/home/user/fraud_cycles.log')


def get_expected_cycles():
    accounts = {}
    with ACCOUNTS.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            accounts[row['account_id']] = {
                'created_at': row['created_at'],
                'status': row['status'],
            }

    edges = defaultdict(float)
    graph = defaultdict(set)
    with TRANSACTIONS.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            src = row['src_account']
            dst = row['dst_account']
            amount = float(row['amount'])
            edges[(src, dst)] = max(edges[(src, dst)], amount)
            graph[src].add(dst)

    cycles = set()
    for a in graph:
        for b in graph[a]:
            if b == a:
                continue
            for c in graph[b]:
                if c == a or c == b:
                    continue
                if a in graph[c]:
                    cycle_nodes = (a, b, c)
                    if any(accounts[node]['status'] != 'ACTIVE' for node in cycle_nodes):
                        continue
                    if not any(accounts[node]['created_at'] > '2023-01-01' for node in cycle_nodes):
                        continue
                    volume = edges[(a, b)] + edges[(b, c)] + edges[(c, a)]
                    if volume <= 10000.0:
                        continue
                    cycles.add(tuple(sorted(cycle_nodes)))

    return [' '.join(cycle) for cycle in sorted(cycles)]


def execute_and_check():
    expected_lines = get_expected_cycles()
    if LOG.exists() or LOG.is_symlink():
        LOG.unlink()

    result = subprocess.run(
        [str(BINARY)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert LOG.is_file(), f'The output file {LOG} does not exist.'

    with LOG.open('r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, (
        f'The contents of {LOG} do not match the expected output.\n'
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(lines)}"
    )


def write_fixture(accounts, transactions):
    with ACCOUNTS.open('w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['account_id', 'created_at', 'status'])
        writer.writerows(accounts)
    with TRANSACTIONS.open('w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['tx_id', 'src_account', 'dst_account', 'amount', 'tx_date'])
        writer.writerows(transactions)


def randomized_fixture(rng, case_number):
    ids = [f'R{case_number}_{i:02d}' for i in range(9)]
    accounts = []
    for account_id in ids:
        date = rng.choice(['2021-03-04', '2022-12-31', '2023-01-01', '2023-04-17', '2024-02-09'])
        status = rng.choice(['ACTIVE', 'ACTIVE', 'SUSPENDED'])
        accounts.append([account_id, date, status])

    # Guarantee at least one qualifying cycle while allowing the oracle to find
    # any additional cycles introduced by the random graph.
    accounts[0][1:] = ['2022-05-01', 'ACTIVE']
    accounts[1][1:] = ['2024-01-15', 'ACTIVE']
    accounts[2][1:] = ['2021-08-20', 'ACTIVE']

    transactions = []
    tx_num = 1
    for src in ids:
        for dst in ids:
            if src != dst and rng.random() < 0.24:
                amount = rng.choice([500.0, 1750.0, 3200.0, 5000.0, 8500.0])
                transactions.append([f'X{tx_num}', src, dst, f'{amount:.2f}', '2025-01-01'])
                tx_num += 1
                if rng.random() < 0.30:
                    other = rng.choice([100.0, 2400.0, 9200.0])
                    transactions.append([f'X{tx_num}', src, dst, f'{other:.2f}', '2025-01-02'])
                    tx_num += 1

    for src, dst, amounts in [
        (ids[0], ids[1], [1200.0, 3500.0]),
        (ids[1], ids[2], [3600.0]),
        (ids[2], ids[0], [3700.0]),
    ]:
        for amount in amounts:
            transactions.append([f'X{tx_num}', src, dst, f'{amount:.2f}', '2025-02-01'])
            tx_num += 1
    rng.shuffle(transactions)
    return accounts, transactions


def test_fraud_cycles_log():
    assert SOURCE.is_file(), f'The required source file {SOURCE} does not exist.'
    assert stat.S_ISREG(SOURCE.stat().st_mode), f'{SOURCE} is not a regular file.'

    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O3', str(SOURCE), '-o', str(BINARY)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f'Compilation failed with status {compile_result.returncode}.\n'
        f'stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}'
    )
    assert BINARY.is_file(), 'Compilation did not produce /home/user/find_cycles.'
    assert os.access(BINARY, os.X_OK), 'The compiled program is not executable.'

    original_accounts = ACCOUNTS.read_bytes()
    original_transactions = TRANSACTIONS.read_bytes()
    saved_log = None
    try:
        # Preserve the original verifier assertion on the supplied fixtures,
        # but require the submitted executable to generate the file itself.
        execute_and_check()
        saved_log = LOG.read_bytes()

        # Explicit boundary and duplicate-edge fixture.
        write_fixture(
            [
                ['A', '2024-01-01', 'ACTIVE'],
                ['B', '2020-01-01', 'ACTIVE'],
                ['C', '2020-01-01', 'ACTIVE'],
                ['D', '2024-01-01', 'SUSPENDED'],
            ],
            [
                ['T1', 'A', 'B', '1000.0', '2025-01-01'],
                ['T2', 'A', 'B', '5000.0', '2025-01-02'],
                ['T3', 'B', 'C', '3000.0', '2025-01-03'],
                ['T4', 'C', 'A', '2500.0', '2025-01-04'],
                ['T5', 'A', 'D', '9000.0', '2025-01-05'],
                ['T6', 'D', 'C', '9000.0', '2025-01-06'],
            ],
        )
        execute_and_check()

        # A validly formatted input with no transactions must create an empty log.
        write_fixture([['ONLY', '2024-01-01', 'ACTIVE']], [])
        execute_and_check()

        # Unpredictable graphs prevent a fixed precomputed log from passing.
        rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
        for case_number in range(4):
            accounts, transactions = randomized_fixture(rng, case_number)
            write_fixture(accounts, transactions)
            execute_and_check()
    finally:
        ACCOUNTS.write_bytes(original_accounts)
        TRANSACTIONS.write_bytes(original_transactions)
        if saved_log is not None:
            LOG.write_bytes(saved_log)
        elif LOG.exists() or LOG.is_symlink():
            LOG.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
