#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
from pathlib import Path
import secrets
import subprocess

LOCKS = Path('/home/user/locks.csv')
OUTPUT = Path('/home/user/deadlock.txt')
EXPECTED_ORIGINAL = 'T02,T04,T06,T08,T03'


def test_deadlock_txt_exists():
    assert os.path.exists(OUTPUT), f'The file {OUTPUT} is missing.'
    assert os.path.isfile(OUTPUT), f'The path {OUTPUT} is not a regular file.'


def test_deadlock_txt_contents():
    with OUTPUT.open('r') as f:
        content = f.read().strip()
    assert content == EXPECTED_ORIGINAL, (
        f'The contents of {OUTPUT} do not match the expected deadlock cycle. '
        f"Expected '{EXPECTED_ORIGINAL}', got '{content}'."
    )


def find_python_scripts():
    candidates = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or path.is_symlink() or path in (LOCKS, OUTPUT):
            continue
        try:
            if path.stat().st_size > 1024 * 1024:
                continue
            source = path.read_text(encoding='utf-8')
            compile(source, str(path), 'exec')
        except (OSError, UnicodeError, SyntaxError):
            continue
        candidates.append(path)
    return candidates


def derive_cycle(rows):
    holder = {
        row['resource_held']: row['tx_id']
        for row in rows
        if row['resource_held']
    }
    graph = {
        row['tx_id']: holder[row['resource_requested']]
        for row in rows
        if row['resource_requested'] in holder
    }

    visited = set()
    cycle = None
    for start in graph:
        if start in visited:
            continue
        order = []
        positions = {}
        current = start
        while current in graph and current not in visited:
            if current in positions:
                cycle = order[positions[current]:]
                break
            positions[current] = len(order)
            order.append(current)
            current = graph[current]
        visited.update(order)
        if cycle is not None:
            break

    assert cycle, 'Generated test data unexpectedly has no cycle'
    smallest = min(cycle)
    index = cycle.index(smallest)
    normalized = cycle[index:] + cycle[:index]
    return ','.join(normalized)


def make_case(rng, cycle_size):
    numbers = rng.sample(range(1000, 9999), cycle_size + 5)
    cycle_ids = [f'T{n}' for n in numbers[:cycle_size]]
    other_ids = [f'T{n}' for n in numbers[cycle_size:]]
    resources = [f'RES_{rng.randrange(10000, 99999)}' for _ in range(cycle_size + 5)]

    rows = []
    for i, tx_id in enumerate(cycle_ids):
        rows.append({
            'tx_id': tx_id,
            'resource_held': resources[i],
            'resource_requested': resources[(i + 1) % cycle_size],
        })

    # A disconnected acyclic chain and unrelated transactions.
    rows.extend([
        {'tx_id': other_ids[0], 'resource_held': resources[cycle_size],
         'resource_requested': resources[cycle_size + 1]},
        {'tx_id': other_ids[1], 'resource_held': resources[cycle_size + 1],
         'resource_requested': ''},
        {'tx_id': other_ids[2], 'resource_held': '',
         'resource_requested': resources[cycle_size]},
        {'tx_id': other_ids[3], 'resource_held': resources[cycle_size + 2],
         'resource_requested': ''},
        {'tx_id': other_ids[4], 'resource_held': '', 'resource_requested': ''},
    ])
    rng.shuffle(rows)
    return rows


def run_script(script, rows):
    with LOCKS.open('w', newline='') as f:
        writer = csv.DictWriter(
            f,
            fieldnames=['tx_id', 'resource_held', 'resource_requested']
        )
        writer.writeheader()
        writer.writerows(rows)

    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    result = subprocess.run(
        ['python3', str(script)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    if result.returncode != 0 or not OUTPUT.is_file():
        return False

    expected = derive_cycle(rows)
    try:
        actual = OUTPUT.read_text().strip()
    except (OSError, UnicodeError):
        return False
    return actual == expected


def test_python_script_parses_and_discovers_cycles():
    scripts = find_python_scripts()
    assert scripts, 'No Python script was found under /home/user.'

    original_locks = LOCKS.read_bytes()
    original_output = OUTPUT.read_bytes()
    rng = secrets.SystemRandom()
    cases = [make_case(rng, size) for size in (2, 3, 5, 6)]
    successful = []

    try:
        for script in scripts:
            try:
                if all(run_script(script, rows) for rows in cases):
                    successful.append(str(script))
            except (OSError, subprocess.SubprocessError):
                pass
    finally:
        LOCKS.write_bytes(original_locks)
        OUTPUT.write_bytes(original_output)

    assert successful, (
        'No submitted Python script correctly parsed /home/user/locks.csv and '
        'generated /home/user/deadlock.txt for independently generated cycles.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
