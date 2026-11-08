#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_config_tracker.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
REMOTE = HOME / 'remote_configs'
LOCAL = HOME / 'local_configs'
INVALID = HOME / 'invalid_files.txt'
ANOMALIES = HOME / 'anomalies.csv'

ORIGINAL_INVALID = [
    '/home/user/local_configs/srv2_t2.json',
    '/home/user/local_configs/srv3_t1.json',
]
ORIGINAL_HEADER = ['server_id', 'metric_name', 'old_value', 'new_value', 'timestamp']
ORIGINAL_ROWS = [
    ['srv1', 'max_conn', '100.0', '160.0', '2'],
    ['srv2', 'max_conn', '500.0', '200.0', '3'],
]


def reset_outputs():
    LOCAL.mkdir(parents=True, exist_ok=True)
    for path in LOCAL.iterdir():
        if path.is_file() or path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    for path in (INVALID, ANOMALIES):
        if path.exists() or path.is_symlink():
            path.unlink()


def run_project(manifest):
    subprocess.run(
        ['cargo', 'build', '--manifest-path', str(manifest)],
        cwd=str(manifest.parent), check=True, timeout=180,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
        cwd=str(manifest.parent), check=True, timeout=180,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def read_invalid():
    assert INVALID.is_file(), f'File {INVALID} is missing.'
    with INVALID.open() as f:
        return [line.strip() for line in f if line.strip()]


def read_anomalies():
    assert ANOMALIES.is_file(), f'File {ANOMALIES} is missing.'
    with ANOMALIES.open(newline='') as f:
        rows = list(csv.reader(f))
    assert rows, f'File {ANOMALIES} is empty.'
    return rows[0], rows[1:]


def assert_copies_preserve_content():
    assert LOCAL.is_dir(), f'Directory {LOCAL} is missing.'
    remote_files = {p.name for p in REMOTE.iterdir() if p.is_file() and p.suffix == '.json'}
    local_files = {p.name for p in LOCAL.iterdir() if p.is_file() and p.suffix == '.json'}
    missing = remote_files - local_files
    assert not missing, f'Files missing in local_configs: {missing}'
    for name in remote_files:
        assert (LOCAL / name).read_bytes() == (REMOTE / name).read_bytes(), \
            f'Local copy {name} does not preserve the remote file content.'


def assert_original_results():
    assert_copies_preserve_content()
    actual_invalid = read_invalid()
    assert actual_invalid == ORIGINAL_INVALID, (
        f'Contents of {INVALID} do not match expected. '
        f'Expected: {ORIGINAL_INVALID}; Found: {actual_invalid}'
    )
    header, rows = read_anomalies()
    assert header == ORIGINAL_HEADER, (
        f'CSV header does not match expected. Expected: {ORIGINAL_HEADER}; Found: {header}'
    )
    assert rows == ORIGINAL_ROWS, (
        f'CSV data rows do not match expected. Expected: {ORIGINAL_ROWS}; Found: {rows}'
    )


def find_rust_projects():
    manifests = []
    preferred = HOME / 'config_tracker' / 'Cargo.toml'
    if preferred.is_file():
        manifests.append(preferred)
    for manifest in HOME.rglob('Cargo.toml'):
        text = str(manifest)
        if '/target/' in text or '/.cargo/' in text or manifest == preferred:
            continue
        manifests.append(manifest)

    usable = []
    for manifest in manifests:
        rust_sources = [p for p in manifest.parent.rglob('*.rs') if '/target/' not in str(p)]
        if rust_sources:
            usable.append(manifest)
    assert usable, 'No Rust Cargo project with Rust source files was found under /home/user.'
    return usable


def select_and_verify_project():
    errors = []
    for manifest in find_rust_projects():
        try:
            reset_outputs()
            run_project(manifest)
            assert_original_results()
            return manifest
        except Exception as exc:
            errors.append(f'{manifest}: {exc}')
    raise AssertionError('No Rust project compiled, ran, and produced the required original results:\n' + '\n'.join(errors))


def expected_for(fixtures):
    invalid = []
    valid = {}
    for filename, obj in fixtures.items():
        metrics = obj['metrics']
        max_conn = float(metrics['max_conn'])
        timeout = float(metrics['timeout'])
        if max_conn <= 0.0 or not (10.0 <= timeout <= 300.0):
            invalid.append(str(LOCAL / filename))
            continue
        valid.setdefault(obj['server_id'], []).append((int(obj['timestamp']), {
            'max_conn': max_conn,
            'timeout': timeout,
        }))

    anomaly_rows = []
    for server_id, records in valid.items():
        records.sort(key=lambda item: item[0])
        for previous, current in zip(records, records[1:]):
            old_metrics = previous[1]
            timestamp, new_metrics = current
            for metric_name in ('max_conn', 'timeout'):
                old = old_metrics[metric_name]
                new = new_metrics[metric_name]
                if abs(new - old) / old > 0.5:
                    anomaly_rows.append([
                        server_id,
                        metric_name,
                        f'{old:.1f}',
                        f'{new:.1f}',
                        str(timestamp),
                    ])
    anomaly_rows.sort(key=lambda row: (row[0], int(row[4]), row[1]))
    return sorted(invalid), anomaly_rows


def run_dynamic_test(manifest):
    token = secrets.token_hex(6)
    server_a = f'alpha_{token}'
    server_b = f'beta_{secrets.token_hex(5)}'
    server_c = f'invalid_{secrets.token_hex(5)}'
    base_a = float(secrets.randbelow(151) + 100)
    base_b = float(secrets.randbelow(301) + 300)

    fixtures = {
        f'{token}_a_late.json': {
            'metrics': {'timeout': 100.0, 'max_conn': base_a * 0.6},
            'timestamp': 40, 'server_id': server_a,
        },
        f'{token}_a_first.json': {
            'server_id': server_a, 'timestamp': 10,
            'metrics': {'max_conn': base_a, 'timeout': 40.0},
        },
        f'{token}_a_threshold.json': {
            'server_id': server_a, 'timestamp': 20,
            'metrics': {'max_conn': base_a * 1.5, 'timeout': 61.0},
        },
        f'{token}_a_invalid_middle.json': {
            'server_id': server_a, 'timestamp': 30,
            'metrics': {'max_conn': base_a * 10.0, 'timeout': 301.0},
        },
        f'{token}_b_first.json': {
            'server_id': server_b, 'timestamp': 5,
            'metrics': {'max_conn': base_b, 'timeout': 10.0},
        },
        f'{token}_b_exact_threshold.json': {
            'server_id': server_b, 'timestamp': 6,
            'metrics': {'max_conn': base_b, 'timeout': 15.0},
        },
        f'{token}_b_anomaly.json': {
            'server_id': server_b, 'timestamp': 7,
            'metrics': {'max_conn': base_b * 1.6, 'timeout': 300.0},
        },
        f'{token}_zero_invalid.json': {
            'server_id': server_c, 'timestamp': 99,
            'metrics': {'max_conn': 0.0, 'timeout': 50.0},
        },
    }

    for path in list(REMOTE.iterdir()):
        if path.is_file() or path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)

    names = list(fixtures)
    secrets.SystemRandom().shuffle(names)
    for name in names:
        # Deliberately use varied whitespace while retaining the exact bytes for copy checks.
        text = json.dumps(fixtures[name], indent=2 if secrets.randbelow(2) else None)
        (REMOTE / name).write_text(text + '\n')

    expected_invalid, expected_rows = expected_for(fixtures)
    reset_outputs()
    run_project(manifest)
    assert_copies_preserve_content()

    actual_invalid = read_invalid()
    assert actual_invalid == expected_invalid, (
        f'Dynamic invalid-file result is wrong. Expected: {expected_invalid}; Found: {actual_invalid}'
    )
    header, rows = read_anomalies()
    assert header == ORIGINAL_HEADER, (
        f'CSV header does not match expected. Expected: {ORIGINAL_HEADER}; Found: {header}'
    )
    assert rows == expected_rows, (
        f'Dynamic anomaly result is wrong. Expected: {expected_rows}; Found: {rows}'
    )


def main():
    assert REMOTE.is_dir(), f'Directory {REMOTE} is missing.'
    backup = Path(tempfile.mkdtemp(prefix='remote_configs_backup_'))
    try:
        for item in REMOTE.iterdir():
            destination = backup / item.name
            if item.is_dir():
                shutil.copytree(item, destination)
            else:
                shutil.copy2(item, destination)

        manifest = select_and_verify_project()
        # Execute the selected Rust application again on unpredictable fixtures.
        run_dynamic_test(manifest)
    finally:
        for item in list(REMOTE.iterdir()):
            if item.is_dir() and not item.is_symlink():
                shutil.rmtree(item)
            else:
                item.unlink()
        for item in backup.iterdir():
            destination = REMOTE / item.name
            if item.is_dir():
                shutil.copytree(item, destination)
            else:
                shutil.copy2(item, destination)
        shutil.rmtree(backup, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_config_tracker.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
