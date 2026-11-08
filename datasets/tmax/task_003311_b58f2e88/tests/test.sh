#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
INPUT = HOME / 'backup_jobs.jsonl'
DEADLOCKS = HOME / 'deadlocks.json'
SCHEDULE = HOME / 'valid_schedule.json'

CANONICAL_JOBS = [
    {'job_id': 'DB_Auth', 'depends_on': []},
    {'job_id': 'DB_Users', 'depends_on': ['DB_Auth']},
    {'job_id': 'DB_Profiles', 'depends_on': ['DB_Users']},
    {'job_id': 'DB_Settings', 'depends_on': ['DB_Users']},
    {'job_id': 'DB_Logs', 'depends_on': []},
    {'job_id': 'DB_Analytics', 'depends_on': ['DB_Logs', 'DB_Profiles']},
    {'job_id': 'DB_Orders', 'depends_on': ['DB_Payments']},
    {'job_id': 'DB_Payments', 'depends_on': ['DB_Invoices']},
    {'job_id': 'DB_Invoices', 'depends_on': ['DB_Orders']},
    {'job_id': 'DB_Inventory', 'depends_on': ['DB_Warehouse']},
    {'job_id': 'DB_Warehouse', 'depends_on': ['DB_Inventory']},
    {'job_id': 'DB_Shipping', 'depends_on': ['DB_Orders']},
    {'job_id': 'DB_Tracking', 'depends_on': ['DB_Shipping']},
]

PROBE_JOBS = [
    {'job_id': 'A', 'depends_on': []},
    {'job_id': 'B', 'depends_on': ['A']},
    {'job_id': 'C', 'depends_on': ['B']},
    {'job_id': 'D', 'depends_on': ['E']},
    {'job_id': 'E', 'depends_on': ['D']},
    {'job_id': 'F', 'depends_on': ['D']},
    {'job_id': 'G', 'depends_on': ['A']},
    {'job_id': 'H', 'depends_on': ['G']},
    {'job_id': 'I', 'depends_on': ['I']},
    {'job_id': 'J', 'depends_on': ['I']},
]


def compute_expected_state(records):
    jobs = {record['job_id']: list(record.get('depends_on', [])) for record in records}

    def get_reachable(start):
        visited = set()
        stack = [start]
        while stack:
            current = stack.pop()
            for dependency in jobs.get(current, []):
                if dependency not in visited:
                    visited.add(dependency)
                    stack.append(dependency)
        return visited

    in_cycle = {job for job in jobs if job in get_reachable(job)}
    cycle_groups = []
    unassigned = set(in_cycle)
    while unassigned:
        start = unassigned.pop()
        component = {start}
        for other in list(unassigned):
            if start in get_reachable(other) and other in get_reachable(start):
                component.add(other)
                unassigned.remove(other)
        cycle_groups.append(sorted(component))
    cycle_groups.sort(key=lambda cycle: cycle[0])

    stuck = set(in_cycle)
    for job in jobs:
        if get_reachable(job).intersection(in_cycle):
            stuck.add(job)

    remaining = set(jobs) - stuck
    job_tier = {}

    def get_tier(job):
        if job in job_tier:
            return job_tier[job]
        dependencies = jobs[job]
        tier = 0 if not dependencies else max(get_tier(dep) for dep in dependencies) + 1
        job_tier[job] = tier
        return tier

    tiers = {}
    for job in remaining:
        tiers.setdefault(get_tier(job), []).append(job)
    schedule = {str(tier): sorted(names) for tier, names in tiers.items()}
    return cycle_groups, schedule


def write_input(records):
    with INPUT.open('w', encoding='utf-8') as handle:
        for record in records:
            handle.write(json.dumps(record) + '\n')


def remove_outputs():
    for output in (DEADLOCKS, SCHEDULE):
        try:
            output.unlink()
        except FileNotFoundError:
            pass


def read_and_check_outputs(records):
    expected_cycles, expected_schedule = compute_expected_state(records)

    assert DEADLOCKS.exists(), f'Output file {DEADLOCKS} is missing.'
    try:
        with DEADLOCKS.open('r', encoding='utf-8') as handle:
            actual_cycles = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f'{DEADLOCKS} does not contain valid JSON.')

    assert isinstance(actual_cycles, list), f'{DEADLOCKS} should contain a list of lists.'
    assert all(isinstance(cycle, list) for cycle in actual_cycles), f'{DEADLOCKS} should contain a list of lists.'
    assert all(isinstance(job, str) for cycle in actual_cycles for job in cycle), 'Cycle job IDs must be strings.'
    assert len(actual_cycles) == len(expected_cycles), f'Expected {len(expected_cycles)} deadlocks, found {len(actual_cycles)}.'
    assert actual_cycles == expected_cycles, f'Deadlocks mismatch. Expected: {expected_cycles}, Actual: {actual_cycles}'

    assert SCHEDULE.exists(), f'Output file {SCHEDULE} is missing.'
    try:
        with SCHEDULE.open('r', encoding='utf-8') as handle:
            actual_schedule = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f'{SCHEDULE} does not contain valid JSON.')

    assert isinstance(actual_schedule, dict), f'{SCHEDULE} should contain a JSON object (dictionary).'
    assert actual_schedule == expected_schedule, f'Valid schedule mismatch. Expected: {expected_schedule}, Actual: {actual_schedule}'


def find_python_scripts():
    excluded = {str(INPUT), str(DEADLOCKS), str(SCHEDULE)}
    candidates = []
    for root, directories, files in os.walk(HOME, followlinks=False):
        directories[:] = [name for name in directories if not (Path(root) / name).is_symlink()]
        for name in files:
            path = Path(root) / name
            if str(path) in excluded:
                continue
            try:
                mode = os.lstat(path).st_mode
                if not stat.S_ISREG(mode) or path.stat().st_size > 2_000_000:
                    continue
                source = path.read_bytes()
                compile(source, str(path), 'exec')
            except (OSError, SyntaxError, ValueError):
                continue
            candidates.append(path)

    def priority(path):
        lower = path.name.lower()
        return (
            0 if path == HOME / 'resolve_backups.py' else 1,
            0 if any(word in lower for word in ('backup', 'deadlock', 'schedule', 'resolve')) else 1,
            0 if path.suffix == '.py' else 1,
            str(path),
        )

    return sorted(candidates, key=priority)


def run_script(script, records):
    write_input(records)
    remove_outputs()
    result = subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{script} exited with status {result.returncode}. '
        f'stdout: {result.stdout[-2000:]} stderr: {result.stderr[-2000:]}'
    )
    read_and_check_outputs(records)


def test_script_and_outputs():
    scripts = find_python_scripts()
    assert scripts, 'No regular Python script was found under /home/user.'

    selected = None
    failures = []
    for script in scripts:
        try:
            run_script(script, PROBE_JOBS)
            selected = script
            break
        except (AssertionError, subprocess.TimeoutExpired) as exc:
            failures.append(f'{script}: {exc}')

    assert selected is not None, 'No submitted Python script produced correct outputs when executed. ' + ' | '.join(failures)

    # Re-run the selected artifact on the original supplied graph. This also leaves
    # the two requested output files in their required final state.
    run_script(selected, CANONICAL_JOBS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
