#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import csv
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pytz

RAW = Path('/home/user/raw_logs.csv')
SUMMARY = Path('/home/user/error_summary.csv')


def read_summary():
    assert SUMMARY.exists(), f'The file {SUMMARY} is missing.'
    assert SUMMARY.is_file(), f'The path {SUMMARY} is not a file.'
    try:
        with SUMMARY.open('r', encoding='utf-8', newline='') as f:
            return list(csv.reader(f))
    except UnicodeDecodeError as exc:
        raise AssertionError(f'The file {SUMMARY} is not properly encoded in UTF-8.') from exc
    except Exception as exc:
        raise AssertionError(f'Failed to read {SUMMARY}: {exc}') from exc


# Preserve the original verifier's exact assertion for the supplied fixture.
original_expected = [
    ['server', 'Auth_Failure', 'DB_Timeout', 'OOM'],
    ['srv-A', '1', '0', '1'],
    ['srv-B', '0', '1', '0'],
    ['srv-C', '0', '0', '1'],
]
original_actual = read_summary()
assert original_actual == original_expected, (
    f'The content of {SUMMARY} does not match the expected output.\n'
    f'Expected: {original_expected}\nActual: {original_actual}'
)


def looks_like_python(path):
    if path.suffix.lower() == '.py':
        return True
    try:
        data = path.read_bytes()
        if len(data) > 2_000_000:
            return False
        first = data.splitlines()[0].lower() if data.splitlines() else b''
        if first.startswith(b'#!') and b'python' in first:
            return True
        text = data.decode('utf-8')
        tree = ast.parse(text, filename=str(path))
        return bool(tree.body)
    except Exception:
        return False


candidates = []
for root, dirs, files in os.walk('/home/user'):
    dirs[:] = [d for d in dirs if d not in {'__pycache__', '.cache', '.git', 'node_modules'}]
    for name in files:
        path = Path(root) / name
        if path in {RAW, SUMMARY} or not path.is_file():
            continue
        if looks_like_python(path):
            candidates.append(path)

assert candidates, 'No Python processing script was found under /home/user.'
candidates.sort(key=lambda p: str(p))


def write_fixture(records):
    with RAW.open('w', encoding='utf-16le', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['local_time', 'timezone', 'server', 'error_category', 'details'])
        writer.writerows(records)


def derive_expected(records):
    filtered = []
    for local_time, zone_name, server, category, details in records:
        naive = datetime.strptime(local_time, '%Y-%m-%d %H:%M:%S')
        aware = pytz.timezone(zone_name).localize(naive, is_dst=None)
        utc_time = aware.astimezone(timezone.utc)
        if utc_time.date().isoformat() == '2024-03-01':
            filtered.append((server, category))

    categories = sorted({category for _, category in filtered})
    servers = sorted({server for server, _ in filtered})
    counts = {(server, category): 0 for server in servers for category in categories}
    for server, category in filtered:
        counts[(server, category)] += 1

    rows = [['server'] + categories]
    rows.extend([
        [server] + [str(counts[(server, category)]) for category in categories]
        for server in servers
    ])
    return rows


fixtures = [
    [
        ('2024-02-29 19:00:00', 'America/New_York', 'alpha', 'Zulu', 'first line\nsecond line, with comma'),
        ('2024-03-01 09:00:00', 'Asia/Tokyo', 'beta', 'Alpha', 'quoted "detail"\nand another line'),
        ('2024-03-01 09:30:00', 'Asia/Tokyo', 'beta', 'Alpha', 'repeat\ntrace'),
        ('2024-03-02 08:59:59', 'Asia/Tokyo', 'gamma', 'Zulu', 'last included second\nstack'),
        ('2024-03-01 16:00:00', 'America/Los_Angeles', 'outside-west', 'Ignored', 'UTC date is March 2'),
        ('2024-03-01 00:00:00', 'Asia/Tokyo', 'outside-east', 'Ignored', 'UTC date is February 29'),
        ('2024-03-02 09:00:00', 'Asia/Tokyo', 'outside-boundary', 'Ignored', 'one second too late'),
    ],
    [
        ('2024-03-01 00:00:00', 'UTC', 'zeta', 'OOM', 'boundary start\nframe 1\nframe 2'),
        ('2024-03-01 23:59:59', 'UTC', 'aardvark', 'DB', 'boundary end, exact'),
        ('2024-03-01 05:45:00', 'Asia/Kathmandu', 'zeta', 'DB', 'non-hour offset\ntrace'),
        ('2024-02-29 14:00:00', 'Pacific/Honolulu', 'middle', 'Weird_Error', 'crosses date line\nwith, comma'),
        ('2024-02-29 13:59:59', 'Pacific/Honolulu', 'too-early', 'Never', 'outside before range'),
        ('2024-03-02 00:00:00', 'UTC', 'too-late', 'Never', 'outside after range'),
    ],
]

raw_backup = RAW.read_bytes()
summary_backup = SUMMARY.read_bytes()
errors = []
passing_script = None

try:
    for candidate in candidates:
        candidate_errors = []
        for index, records in enumerate(fixtures, start=1):
            write_fixture(records)
            if SUMMARY.exists():
                if SUMMARY.is_dir():
                    shutil.rmtree(SUMMARY)
                else:
                    SUMMARY.unlink()

            try:
                result = subprocess.run(
                    [sys.executable, str(candidate)],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
            except Exception as exc:
                candidate_errors.append(f'fixture {index}: execution failed: {exc}')
                break

            if result.returncode != 0:
                candidate_errors.append(
                    f'fixture {index}: exited {result.returncode}; stderr={result.stderr[-1000:]!r}'
                )
                break

            try:
                actual = read_summary()
                expected = derive_expected(records)
                assert actual == expected, f'expected {expected!r}, got {actual!r}'
            except Exception as exc:
                candidate_errors.append(f'fixture {index}: {exc}')
                break

        if not candidate_errors:
            passing_script = candidate
            break
        errors.append(f'{candidate}: ' + '; '.join(candidate_errors))
finally:
    RAW.write_bytes(raw_backup)
    SUMMARY.write_bytes(summary_backup)

assert passing_script is not None, (
    'No submitted Python script correctly processed the UTF-16LE CSV on dynamic fixtures. '
    + ' | '.join(errors)
)
print(f'Validated processing script: {passing_script}')
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
