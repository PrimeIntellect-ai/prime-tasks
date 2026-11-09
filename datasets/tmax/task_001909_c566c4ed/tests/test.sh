#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

INPUT_PATH = Path('/home/user/loc_telemetry.csv')
OUTPUT_PATH = Path('/home/user/aggregated_loc_stats.csv')

EXPECTED_ORIGINAL = [
    ['bucket_start_iso8601', 'locale', 'avg_render_time_ms'],
    ['2023-10-15T10:00:00Z', 'de-DE', '0.0'],
    ['2023-10-15T10:00:00Z', 'es-ES', '45.0'],
    ['2023-10-15T10:00:00Z', 'fr-FR', '60.0'],
    ['2023-10-15T10:01:00Z', 'de-DE', '0.0'],
    ['2023-10-15T10:01:00Z', 'es-ES', '0.0'],
    ['2023-10-15T10:01:00Z', 'fr-FR', '0.0'],
    ['2023-10-15T10:02:00Z', 'de-DE', '100.0'],
    ['2023-10-15T10:02:00Z', 'es-ES', '0.0'],
    ['2023-10-15T10:02:00Z', 'fr-FR', '0.0'],
    ['2023-10-15T10:03:00Z', 'de-DE', '0.0'],
    ['2023-10-15T10:03:00Z', 'es-ES', '0.0'],
    ['2023-10-15T10:03:00Z', 'fr-FR', '0.0'],
    ['2023-10-15T10:04:00Z', 'de-DE', '0.0'],
    ['2023-10-15T10:04:00Z', 'es-ES', '0.0'],
    ['2023-10-15T10:04:00Z', 'fr-FR', '80.0'],
]


def read_output():
    assert OUTPUT_PATH.is_file(), f'Expected output file {OUTPUT_PATH} does not exist.'
    with OUTPUT_PATH.open('r', newline='', encoding='utf-8') as f:
        return [row for row in csv.reader(f) if row]


def assert_rows(expected):
    actual = read_output()
    assert len(actual) == len(expected), f'Expected {len(expected)} rows, but got {len(actual)} rows in {OUTPUT_PATH}.'
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f'Row {i} mismatch. Expected {want}, got {got}.'


def parse_timestamp(value):
    if value.lstrip('-').isdigit():
        return datetime.fromtimestamp(int(value), tz=timezone.utc)
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)


def expected_for(records):
    aggregates = {}
    locales = set()
    buckets = []
    for timestamp, locale, _key, value in records:
        dt = parse_timestamp(timestamp).replace(second=0, microsecond=0)
        locales.add(locale)
        buckets.append(dt)
        aggregates.setdefault((dt, locale), []).append(Decimal(str(value)))

    current = min(buckets)
    maximum = max(buckets)
    rows = [['bucket_start_iso8601', 'locale', 'avg_render_time_ms']]
    while current <= maximum:
        stamp = current.strftime('%Y-%m-%dT%H:%M:%SZ')
        for locale in sorted(locales):
            values = aggregates.get((current, locale))
            if values:
                average = sum(values) / Decimal(len(values))
                rendered = str(average.quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))
            else:
                rendered = '0.0'
            rows.append([stamp, locale, rendered])
        current += timedelta(minutes=1)
    return rows


def write_fixture(records):
    with INPUT_PATH.open('w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['timestamp', 'locale', 'key', 'render_time_ms'])
        writer.writerows(records)


def discover_runners():
    manifests = []
    rust_files = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'target', '.cargo', '.git'}]
        root_path = Path(root)
        if 'Cargo.toml' in files:
            manifests.append(root_path / 'Cargo.toml')
        for name in files:
            if name.endswith('.rs'):
                rust_files.append(root_path / name)

    preferred = Path('/home/user/loc_analyzer/Cargo.toml')
    manifests = sorted(set(manifests), key=lambda p: (p != preferred, str(p)))
    runners = []
    for manifest in manifests:
        source_dir = manifest.parent / 'src'
        if source_dir.is_dir() and any(source_dir.rglob('*.rs')):
            runners.append(('cargo', manifest))

    for i, source in enumerate(sorted(set(rust_files))):
        runners.append(('rustc', source, Path(f'/tmp/loc_analyzer_verifier_{i}')))
    return runners


def execute_runner(runner):
    env = os.environ.copy()
    if runner[0] == 'cargo':
        manifest = runner[1]
        subprocess.run(
            ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
            cwd=str(manifest.parent), env=env, check=True, timeout=120,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
    else:
        source, binary = runner[1], runner[2]
        subprocess.run(
            ['rustc', str(source), '-o', str(binary)],
            cwd=str(source.parent), env=env, check=True, timeout=120,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        subprocess.run(
            [str(binary)], cwd=str(source.parent), env=env, check=True, timeout=120,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )


def test_aggregated_loc_stats_csv_exists_and_correct_and_is_generated_by_rust():
    # Retain the original fixed-fixture assertion.
    assert_rows(EXPECTED_ORIGINAL)

    original_input = INPUT_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes()
    token = secrets.token_hex(3)
    base = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=secrets.randbelow(250), minutes=secrets.randbelow(1000)
    )
    base = base.replace(second=0, microsecond=0)
    value = 20 + secrets.randbelow(50)
    locales = [f'aa-{token}', f'mm-{token}', f'zz-{token}']

    offset_time = base + timedelta(hours=2, seconds=47)
    fixture_one = [
        ((base + timedelta(seconds=8)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[0], 'k1', value),
        ((base + timedelta(seconds=27)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[0], 'k2', value + 1),
        ((base + timedelta(seconds=51)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[0], 'k3', value + 1),
        (str(int((base + timedelta(minutes=1, seconds=14)).timestamp())), locales[1], 'k4', value + 9),
        (offset_time.strftime('%Y-%m-%dT%H:%M:%S+02:00'), locales[2], 'k5', value + 15),
        ((base + timedelta(minutes=4, seconds=3)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[1], 'k6', value + 20),
    ]

    fixture_two_base = base + timedelta(days=17, hours=3)
    fixture_two = [
        (str(int((fixture_two_base + timedelta(seconds=59)).timestamp())), locales[2], 'a', value + 3),
        ((fixture_two_base + timedelta(minutes=2, seconds=1)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[0], 'b', value + 6),
        (str(int((fixture_two_base + timedelta(minutes=2, seconds=48)).timestamp())), locales[0], 'c', value + 10),
        ((fixture_two_base + timedelta(minutes=5, seconds=22)).strftime('%Y-%m-%dT%H:%M:%SZ'), locales[1], 'd', value + 30),
    ]

    try:
        write_fixture(fixture_one)
        expected_one = expected_for(fixture_one)
        runners = discover_runners()
        assert runners, 'No Rust source file or Cargo project was found under /home/user.'

        selected = None
        failures = []
        for runner in runners:
            try:
                if OUTPUT_PATH.exists():
                    OUTPUT_PATH.unlink()
                execute_runner(runner)
                assert_rows(expected_one)
                selected = runner
                break
            except Exception as exc:
                failures.append(f'{runner}: {exc}')

        assert selected is not None, 'No discovered Rust program generated the required output for a new fixture. ' + ' | '.join(failures[-4:])

        write_fixture(fixture_two)
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        execute_runner(selected)
        assert_rows(expected_for(fixture_two))
    finally:
        INPUT_PATH.write_bytes(original_input)
        OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
