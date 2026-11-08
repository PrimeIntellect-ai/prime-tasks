#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import re
import shutil
import stat
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

FILTER = Path('/home/user/filter.py')
REPORT = Path('/home/user/report.txt')


def run_filter(path):
    return subprocess.run(
        ['python3', str(FILTER), str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    ).returncode


def write_csv(path, header, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def test_filter_py_exists():
    assert FILTER.exists(), 'Missing /home/user/filter.py script.'


def test_report_exists():
    assert REPORT.exists(), 'Missing /home/user/report.txt. Ensure the ETL pipeline and modeling step completed.'
    assert REPORT.stat().st_size > 0, '/home/user/report.txt is empty.'


def test_filter_clean_corpus():
    clean_dir = '/app/corpora/clean'
    clean_files = glob.glob(os.path.join(clean_dir, '*.csv'))
    assert len(clean_files) > 0, f'No clean corpus files found in {clean_dir}.'

    modified_clean = []
    for f in clean_files:
        if run_filter(f) != 0:
            modified_clean.append(os.path.basename(f))

    if modified_clean:
        pytest.fail(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected instead of preserved): {', '.join(modified_clean)}")


def test_filter_evil_corpus():
    evil_dir = '/app/corpora/evil'
    evil_files = glob.glob(os.path.join(evil_dir, '*.csv'))
    assert len(evil_files) > 0, f'No evil corpus files found in {evil_dir}.'

    bypassed_evil = []
    for f in evil_files:
        if run_filter(f) != 1:
            bypassed_evil.append(os.path.basename(f))

    if bypassed_evil:
        pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed (accepted instead of rejected): {', '.join(bypassed_evil)}")


def test_filter_generated_hidden_cases(tmp_path):
    rng = random.Random(918273)
    cases = []

    for _ in range(12):
        name = f'{rng.getrandbits(64):016x}.csv'
        rows = []
        for _ in range(rng.randint(1, 5)):
            rows.append([
                rng.randint(10000, 99999),
                rng.uniform(-80.0, 60.0),
                rng.uniform(0.0, 100.0),
                rng.uniform(850.0, 1150.0),
            ])
        path = tmp_path / name
        write_csv(path, ['reading_id', 'temperature', 'humidity', 'pressure'], rows)
        cases.append((path, 0))

    corrupt_rows = [
        [70001, -273.151, 50.0, 1000.0],
        [70002, 20.0, -0.01, 1000.0],
        [70003, 20.0, 100.01, 1000.0],
    ]
    for row in corrupt_rows:
        path = tmp_path / f'{rng.getrandbits(64):016x}.csv'
        write_csv(path, ['reading_id', 'temperature', 'humidity', 'pressure'], [row])
        cases.append((path, 1))

    malformed = [
        (['reading_id', 'temperature', 'humidity'], [[80001, 20.0, 50.0]]),
        (['reading_id', 'temperature', 'humidity', 'pressure', 'extra'], [[80002, 20.0, 50.0, 1000.0, 1]]),
        (['reading_id', 'temperature', 'humidity', 'pressure'], [[80003, 'not-a-number', 50.0, 1000.0]]),
        (['reading_id', 'temperature', 'humidity', 'pressure'], [[80004, 20.0, '', 1000.0]]),
    ]
    for header, rows in malformed:
        path = tmp_path / f'{rng.getrandbits(64):016x}.csv'
        write_csv(path, header, rows)
        cases.append((path, 1))

    rng.shuffle(cases)
    failures = []
    for path, expected in cases:
        actual = run_filter(path)
        if actual != expected:
            failures.append(f'{path.name}: expected {expected}, got {actual}')
    assert not failures, 'Generated filter cases failed: ' + '; '.join(failures)


def discover_pipeline_scripts():
    scripts = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or path == FILTER or path == REPORT:
            continue
        if path.suffix.lower() in {'.py', '.sh'}:
            scripts.append(path)
            continue
        try:
            if os.access(path, os.X_OK) and path.read_bytes()[:2] == b'#!':
                scripts.append(path)
        except OSError:
            pass
    return sorted(scripts, key=lambda p: str(p))[:20]


def script_command(path):
    if path.suffix.lower() == '.py':
        return ['python3', str(path)]
    if path.suffix.lower() == '.sh':
        return ['bash', str(path)]
    return [str(path)]


def report_looks_standard(text):
    lower = text.lower()
    required = ['precision', 'recall', 'f1-score', 'support']
    if not all(word in lower for word in required):
        return False
    class_rows = []
    for line in text.splitlines():
        if any(x in line.lower() for x in ('accuracy', 'macro avg', 'weighted avg', 'micro avg')):
            continue
        if re.match(r'^\s*\S+\s+[-+]?\d*\.?\d+\s+[-+]?\d*\.?\d+\s+[-+]?\d*\.?\d+\s+\d+\s*$', line):
            class_rows.append(line)
    return len(class_rows) >= 2 and ('accuracy' in lower or 'macro avg' in lower)


def test_pipeline_is_executable_and_regenerates_model_report(tmp_path):
    scripts = discover_pipeline_scripts()
    assert scripts, 'No ETL/modeling script was created under /home/user.'

    source = ''
    for script in scripts:
        try:
            source += '\n' + script.read_text(errors='ignore')
        except OSError:
            pass
    lower_source = source.lower()
    assert 'metadata' in lower_source, 'Pipeline scripts do not join or read the metadata.'
    assert ('bootstrap' in lower_source or 'upsampl' in lower_source or
            'resampl' in lower_source or
            re.search(r'replace\s*=\s*true', lower_source) or
            'random.choice' in lower_source or 'random.choices' in lower_source), \
        'Pipeline scripts do not implement bootstrap up-sampling.'
    assert ('.fit(' in lower_source or '.train(' in lower_source), \
        'Pipeline scripts do not train a classification model.'
    assert ('classification_report' in lower_source or 'classification report' in lower_source), \
        'Pipeline scripts do not produce a standard classification report.'

    raw_dir = Path('/app/data/raw')
    metadata = Path('/app/data/metadata.csv')
    decoder = Path('/app/sensor_decode')
    backup_root = Path(tempfile.mkdtemp(prefix='pipeline_backup_'))
    raw_backup = backup_root / 'raw'
    metadata_backup = backup_root / 'metadata.csv'
    decoder_backup = backup_root / 'sensor_decode.real'
    filter_backup = backup_root / 'filter.real.py'
    decode_log = backup_root / 'decode.log'
    filter_log = backup_root / 'filter.log'

    shutil.copytree(raw_dir, raw_backup)
    shutil.copy2(metadata, metadata_backup)
    shutil.copy2(decoder, decoder_backup)
    shutil.copy2(FILTER, filter_backup)

    rng = random.Random(445566)
    expected_files = 140

    try:
        shutil.rmtree(raw_dir)
        raw_dir.mkdir(parents=True)
        rows = []
        base_id = rng.randint(200000, 400000)
        for i in range(expected_files):
            rid = base_id + i * 7
            if i < 100:
                status = 'Normal'
                temp = rng.uniform(-15.0, 12.0)
                hum = rng.uniform(25.0, 75.0)
            elif i < 120:
                status = 'Warning'
                temp = rng.uniform(35.0, 55.0)
                hum = rng.uniform(25.0, 75.0)
            elif i % 2:
                status = 'Normal'
                temp = rng.uniform(-450.0, -300.0)
                hum = rng.uniform(25.0, 75.0)
            else:
                status = 'Normal'
                temp = rng.uniform(-10.0, 30.0)
                hum = rng.uniform(-40.0, -1.0)
            pressure = rng.uniform(920.0, 1080.0)
            filename = f'{rng.getrandbits(64):016x}.bin'
            with open(raw_dir / filename, 'wb') as f:
                f.write(struct.pack('ifff', rid, temp, hum, pressure))
            rows.append((rid, status))

        with open(metadata, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['reading_id', 'status'])
            writer.writerows(rows)

        decoder.write_text(
            '#!/usr/bin/env python3\n'
            'import os, subprocess, sys\n'
            f"open({str(decode_log)!r}, 'a').write(sys.argv[1] + '\\n')\n"
            f"raise SystemExit(subprocess.run([{str(decoder_backup)!r}] + sys.argv[1:]).returncode)\n"
        )
        decoder.chmod(0o755)

        FILTER.write_text(
            '#!/usr/bin/env python3\n'
            'import subprocess, sys\n'
            f"open({str(filter_log)!r}, 'a').write((sys.argv[1] if len(sys.argv) > 1 else '') + '\\n')\n"
            f"raise SystemExit(subprocess.run(['python3', {str(filter_backup)!r}] + sys.argv[1:]).returncode)\n"
        )
        FILTER.chmod(0o755)

        successes = []
        diagnostics = []
        for script in scripts:
            decode_log.write_text('')
            filter_log.write_text('')
            if REPORT.exists():
                REPORT.unlink()
            try:
                result = subprocess.run(
                    script_command(script),
                    cwd=str(script.parent),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=120,
                    env=dict(os.environ, PYTHONUNBUFFERED='1'),
                )
            except subprocess.TimeoutExpired:
                diagnostics.append(f'{script}: timed out')
                continue

            decoded = len(decode_log.read_text().splitlines())
            filtered = len(filter_log.read_text().splitlines())
            report_text = REPORT.read_text(errors='replace') if REPORT.exists() else ''
            if (result.returncode == 0 and decoded >= expected_files and
                    filtered >= expected_files and report_looks_standard(report_text)):
                successes.append(str(script))
                break
            diagnostics.append(
                f'{script}: exit={result.returncode}, decoded={decoded}, '
                f'filtered={filtered}, report_valid={report_looks_standard(report_text)}'
            )

        assert successes, (
            'No pipeline script successfully decoded and filtered every generated input, '
            'trained/evaluated, and regenerated a standard classification report. ' +
            ' | '.join(diagnostics)
        )
    finally:
        if raw_dir.exists():
            shutil.rmtree(raw_dir)
        shutil.copytree(raw_backup, raw_dir)
        shutil.copy2(metadata_backup, metadata)
        shutil.copy2(decoder_backup, decoder)
        decoder.chmod(0o755)
        shutil.copy2(filter_backup, FILTER)
        FILTER.chmod(filter_backup.stat().st_mode | stat.S_IXUSR)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
