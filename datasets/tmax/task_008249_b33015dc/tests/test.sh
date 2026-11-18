#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

SCRIPT = Path('/home/user/config_analyzer.py')
DATA_DIR = Path('/home/user/data')
RESULTS = Path('/home/user/results.csv')
ALERTS = Path('/home/user/alerts.csv')
HEADER = ['server_id', 'timestamp', 'similarity', 'rolling_avg']
FOUR_DP = re.compile(r'^-?\d+\.\d{4}$')


def compute_expected(records):
    grouped = defaultdict(list)
    for record in records:
        grouped[record['server_id']].append(record)

    output = []
    for server_id in sorted(grouped):
        server_records = sorted(grouped[server_id], key=lambda item: item['timestamp'])
        similarities = []
        for index in range(len(server_records) - 1):
            left = {f'{key}={value}' for key, value in server_records[index]['config'].items()}
            right = {f'{key}={value}' for key, value in server_records[index + 1]['config'].items()}
            union = left | right
            similarity = len(left & right) / len(union) if union else 1.0
            similarities.append(similarity)
            rolling = sum(similarities[-3:]) / len(similarities[-3:])
            output.append((server_id, server_records[index + 1]['timestamp'], similarity, rolling))

    output.sort(key=lambda item: (item[0], item[1]))
    return output


def original_records():
    random.seed(42)
    servers = [f'server_{i:03d}' for i in range(10)]
    base_config = {f'key{i}': 'val0' for i in range(10)}
    records = []

    for file_idx in range(3):
        for t in range(20):
            for server_id in servers:
                timestamp = 1600000000 + t * 3600 + file_idx * 86400 + random.randint(0, 60)
                config = base_config.copy()
                if random.random() < 0.2:
                    config[f'key{random.randint(0, 9)}'] = f'val{random.randint(1, 5)}'
                elif random.random() < 0.05:
                    for _ in range(5):
                        config[f'key{random.randint(0, 9)}'] = f'val{random.randint(10, 20)}'
                records.append({'server_id': server_id, 'timestamp': timestamp, 'config': config})
    return records


def read_and_check_csv(path, expected, label):
    assert path.is_file(), f'The file {path} does not exist.'
    with path.open('r', encoding='utf-8', newline='') as handle:
        rows = list(csv.reader(handle))

    assert rows, f'{label} is empty.'
    assert rows[0] == HEADER, f'Incorrect header in {label}.'
    actual = rows[1:]
    assert len(actual) == len(expected), f'Expected {len(expected)} rows in {label}, but got {len(actual)}.'

    for index, (row, exp) in enumerate(zip(actual, expected), 1):
        assert len(row) == 4, f'Row {index} of {label} does not have exactly four columns.'
        assert row[0] == exp[0], f'Row {index}: expected server_id {exp[0]}, got {row[0]}'
        assert row[1] == str(exp[1]), f'Row {index}: expected timestamp {exp[1]}, got {row[1]}'
        assert FOUR_DP.fullmatch(row[2]), f'Row {index}: similarity is not formatted to exactly four decimal places: {row[2]}'
        assert FOUR_DP.fullmatch(row[3]), f'Row {index}: rolling_avg is not formatted to exactly four decimal places: {row[3]}'
        assert row[2] == f'{exp[2]:.4f}', f'Row {index}: expected similarity {exp[2]:.4f}, got {row[2]}'
        assert row[3] == f'{exp[3]:.4f}', f'Row {index}: expected rolling_avg {exp[3]:.4f}, got {row[3]}'


def check_multiprocessing_usage():
    source = SCRIPT.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(SCRIPT))
    module_aliases = set()
    constructor_aliases = set()
    imported = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing':
                    imported = True
                    module_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == 'multiprocessing':
            imported = True
            for alias in node.names:
                if alias.name in {'Pool', 'Process'}:
                    constructor_aliases.add(alias.asname or alias.name)

    constructed = False
    parallel_operation = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in constructor_aliases:
            constructed = True
        elif (isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name)
              and func.value.id in module_aliases and func.attr in {'Pool', 'Process'}):
            constructed = True
        if isinstance(func, ast.Attribute) and func.attr in {'map', 'starmap', 'imap', 'imap_unordered', 'apply_async', 'map_async', 'start'}:
            parallel_operation = True

    assert imported, 'config_analyzer.py must import Python multiprocessing.'
    assert constructed and parallel_operation, 'config_analyzer.py must use multiprocessing workers to process servers in parallel.'


def make_fixture(seed):
    rng = random.Random(seed)
    records = []
    server_ids = [f'dynamic_{seed:x}_{i}' for i in range(5)]
    for server_index, server_id in enumerate(server_ids):
        config = {f'k{i}': f'base_{server_index}_{i}' for i in range(6)}
        for step in range(8):
            current = dict(config)
            mode = (step + server_index + seed) % 5
            if mode == 1:
                current['k0'] = f'minor_{step}_{rng.randrange(1000)}'
            elif mode == 2:
                for key in ('k0', 'k1', 'k2', 'k3'):
                    current[key] = f'major_{step}_{key}_{rng.randrange(1000)}'
            elif mode == 3:
                current.pop('k5', None)
                current[f'extra_{step}'] = str(rng.randrange(1000))
            elif mode == 4:
                current['k2'] = f'changed={rng.randrange(1000)}'
            timestamp = 1900000000 + server_index * 100000 + step * 137 + rng.randrange(1, 20)
            records.append({'server_id': server_id, 'timestamp': timestamp, 'config': current})
            config = current
    rng.shuffle(records)
    return records


def install_fixture(records):
    for entry in DATA_DIR.iterdir():
        if entry.is_dir():
            shutil.rmtree(entry)
        else:
            entry.unlink()

    buckets = [[], [], []]
    for index, record in enumerate(records):
        buckets[index % len(buckets)].append(record)
    for index, bucket in enumerate(buckets):
        with (DATA_DIR / f'fixture_{index}.jsonl').open('w', encoding='utf-8') as handle:
            for record in bucket:
                handle.write(json.dumps(record, sort_keys=True) + '\n')
    (DATA_DIR / 'ignore_me.txt').write_text('this is not JSON and must not be read\n', encoding='utf-8')


def main():
    assert SCRIPT.is_file() and not SCRIPT.is_symlink(), 'The script /home/user/config_analyzer.py does not exist as a regular file.'
    compile(SCRIPT.read_text(encoding='utf-8'), str(SCRIPT), 'exec')
    check_multiprocessing_usage()

    # Preserve the original verifier's checks against the supplied deterministic data.
    expected_original = compute_expected(original_records())
    read_and_check_csv(RESULTS, expected_original, 'results.csv')
    expected_alerts = [row for row in expected_original if row[3] < 0.5000]
    read_and_check_csv(ALERTS, expected_alerts, 'alerts.csv')

    temp_root = Path(tempfile.mkdtemp(prefix='config-verifier-'))
    data_backup = temp_root / 'data'
    shutil.copytree(DATA_DIR, data_backup)
    saved_results = RESULTS.read_bytes() if RESULTS.exists() else None
    saved_alerts = ALERTS.read_bytes() if ALERTS.exists() else None

    try:
        for seed in (8675309, 31415927):
            records = make_fixture(seed)
            install_fixture(records)
            if RESULTS.exists():
                RESULTS.unlink()

            completed = subprocess.run(
                ['python3', str(SCRIPT)],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=45,
            )
            assert completed.returncode == 0, (
                f'config_analyzer.py failed on verifier-generated input with exit code {completed.returncode}.\n'
                f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
            )
            read_and_check_csv(RESULTS, compute_expected(records), f'results.csv for dynamic fixture {seed}')
    finally:
        if DATA_DIR.exists():
            shutil.rmtree(DATA_DIR)
        shutil.copytree(data_backup, DATA_DIR)
        if saved_results is None:
            RESULTS.unlink(missing_ok=True)
        else:
            RESULTS.write_bytes(saved_results)
        if saved_alerts is None:
            ALERTS.unlink(missing_ok=True)
        else:
            ALERTS.write_bytes(saved_alerts)
        shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
