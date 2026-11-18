#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import unicodedata
from pathlib import Path

DATA_DIR = Path('/home/user/data')
RAW = DATA_DIR / 'raw_metrics.jsonl'
OUTPUT = DATA_DIR / 'normalized_metrics.csv'


def check_original_assertions():
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist.'
    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))

    expected_rows = [
        ['normalized_id', 'timestamp', 'measurement', 'rolling_sma'],
        ['sensor_A', '1', '10.00', '10.00'],
        ['sensor_A', '2', '20.00', '15.00'],
        ['sensor_A', '3', '30.00', '20.00'],
        ['sensor_A', '4', '40.00', '30.00'],
        ['sensor_Å', '10', '5.00', '5.00'],
        ['sensor_Å', '11', '15.00', '10.00'],
        ['sensor_Å', '12', '10.00', '10.00'],
    ]
    assert len(rows) == len(expected_rows), f'Expected {len(expected_rows)} rows, but got {len(rows)}.'
    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual == expected, f'Row {i + 1} mismatch. Expected {expected}, got {actual}.'


def find_and_build_rust_application():
    manifests = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'target', '.git', '.cargo'}]
        if 'Cargo.toml' in files:
            manifests.append(Path(root) / 'Cargo.toml')

    manifests.sort(key=lambda p: (0 if str(p).startswith('/home/user/metrics_processor/') else 1, len(str(p))))
    assert manifests, 'No Cargo.toml for a Rust application was found under /home/user.'

    failures = []
    for manifest in manifests:
        project = manifest.parent
        rust_files = [p for p in project.rglob('*.rs') if 'target' not in p.parts]
        if not rust_files:
            continue
        source = '\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in rust_files)
        cargo_text = manifest.read_text(encoding='utf-8', errors='ignore')

        parallel_markers = (
            'par_iter', 'into_par_iter', 'par_bridge', 'rayon::',
            'thread::spawn', 'thread::scope', 'std::thread',
            'crossbeam::', 'tokio::spawn', 'spawn_blocking',
        )
        if not any(marker in source for marker in parallel_markers):
            failures.append(f'{manifest}: no Rust parallel-processing construct found')
            continue
        if ('rayon' in source.lower()) != ('rayon' in cargo_text.lower()) and 'rayon' in source.lower():
            failures.append(f'{manifest}: Rayon is used but is not declared in Cargo.toml')
            continue

        try:
            metadata = json.loads(subprocess.check_output(
                ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', str(manifest)],
                cwd=project, text=True, stderr=subprocess.STDOUT, timeout=60,
            ))
            package = next((p for p in metadata['packages'] if Path(p['manifest_path']).resolve() == manifest.resolve()), None)
            if package is None:
                failures.append(f'{manifest}: package metadata not found')
                continue
            bins = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
            if len(bins) != 1:
                failures.append(f'{manifest}: expected exactly one executable target, found {len(bins)}')
                continue
            bin_name = bins[0]['name']
            subprocess.run(
                ['cargo', 'build', '--manifest-path', str(manifest), '--bin', bin_name],
                cwd=project, check=True, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, timeout=240,
            )
            executable = Path(metadata['target_directory']) / 'debug' / bin_name
            assert executable.is_file(), f'Cargo did not produce executable {executable}'
            assert os.access(executable, os.X_OK), f'Built Rust artifact is not executable: {executable}'
            return executable, project
        except Exception as exc:
            failures.append(f'{manifest}: {exc}')

    raise AssertionError('No runnable Rust application with parallel processing was found. ' + '; '.join(failures))


def unescape_literal_unicode(value):
    return re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), value)


def expected_csv(records):
    groups = {}
    for record in records:
        normalized = unicodedata.normalize('NFKC', unescape_literal_unicode(record['id']))
        groups.setdefault(normalized, []).append(record)

    result = [['normalized_id', 'timestamp', 'measurement', 'rolling_sma']]
    for normalized in sorted(groups):
        ordered = sorted(groups[normalized], key=lambda r: r['timestamp'])
        for i, record in enumerate(ordered):
            window = ordered[max(0, i - 2):i + 1]
            sma = sum(float(r['measurement']) for r in window) / len(window)
            result.append([
                normalized,
                str(record['timestamp']),
                f"{float(record['measurement']):.2f}",
                f'{sma:.2f}',
            ])
    return result


def exercise_application(executable, cwd):
    token = secrets.token_hex(6)
    base = secrets.randbelow(50000) + 1000
    records = [
        {'id': f'{token}_Ａ', 'timestamp': base + 40, 'measurement': 40.0},
        {'id': f'{token}_\\u0041', 'timestamp': base + 10, 'measurement': 10.0},
        {'id': f'{token}_A', 'timestamp': base + 30, 'measurement': 30.0},
        {'id': f'{token}_\uff21', 'timestamp': base + 20, 'measurement': 20.0},
        {'id': f'{token},ring_Å', 'timestamp': base + 3, 'measurement': 15.0},
        {'id': f'{token},ring_\\u00C5', 'timestamp': base + 1, 'measurement': -5.0},
        {'id': f'{token},ring_A\u030A', 'timestamp': base + 2, 'measurement': 5.0},
        {'id': f'{token}_quoted_“x”', 'timestamp': base + 8, 'measurement': 2.75},
        {'id': f'{token}_quoted_\\u201Cx\\u201D', 'timestamp': base + 7, 'measurement': 1.25},
    ]
    random.SystemRandom().shuffle(records)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with RAW.open('w', encoding='utf-8', newline='\n') as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=True, separators=(',', ':')) + '\n')

    if OUTPUT.exists():
        OUTPUT.unlink()

    subprocess.run(
        [str(executable)], cwd=cwd, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    assert OUTPUT.is_file(), 'The executed Rust application did not create normalized_metrics.csv.'

    with OUTPUT.open('r', encoding='utf-8', newline='') as f:
        actual = list(csv.reader(f))
    expected = expected_csv(records)
    assert actual == expected, f'Dynamic-input CSV mismatch.\nExpected: {expected!r}\nActual: {actual!r}'


def main():
    check_original_assertions()
    executable, cwd = find_and_build_rust_application()
    exercise_application(executable, cwd)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
