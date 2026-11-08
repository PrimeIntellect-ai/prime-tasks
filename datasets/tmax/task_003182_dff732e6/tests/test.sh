#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import subprocess
import time
from decimal import Decimal
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'dataset_raw'
PROCESSED = HOME / 'dataset_processed'
BACKUP = HOME / 'backup'


def run_checked(args, timeout=20):
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {args!r} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def archive_members(path):
    result = run_checked(['tar', '-tzf', str(path)])
    return [line.strip().lstrip('./') for line in result.stdout.splitlines() if line.strip()]


def test_complete_task():
    # Preserve the original final-state assertions.
    summary_path = PROCESSED / 'summary.txt'
    assert summary_path.is_file(), f"File {summary_path} is missing."
    content = summary_path.read_text(encoding='utf-8').splitlines()
    expected_lines = [
        'sensor_A.csv: 30.7',
        'sensor_B.csv: 150.4',
    ]
    for expected in expected_lines:
        assert expected in content, f"Expected line '{expected}' not found in {summary_path}"

    script_path = HOME / 'backup.sh'
    assert script_path.is_file(), f"Backup script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Backup script {script_path} is not executable."

    snapshot_path = BACKUP / 'snapshot.snar'
    assert snapshot_path.is_file(), f"Snapshot file {snapshot_path} is missing."

    assert BACKUP.is_dir(), f"Backup directory {BACKUP} is missing."
    initial_archives = [Path(p) for p in glob.glob(str(BACKUP / '*.tar.gz'))]
    assert len(initial_archives) == 1, (
        f"Expected exactly one .tar.gz file in {BACKUP}, found {len(initial_archives)}."
    )

    # The initial backup must be a real, correctly named tar.gz containing the output.
    initial_archive = initial_archives[0]
    assert re.fullmatch(r'backup_[0-9]+\.tar\.gz', initial_archive.name), (
        f"Backup archive has an invalid name: {initial_archive.name}"
    )
    assert initial_archive.stat().st_size > 0, 'The initial backup archive is empty.'
    initial_members = archive_members(initial_archive)
    assert any(name.endswith('dataset_processed/summary.txt') for name in initial_members), (
        'The initial archive does not contain dataset_processed/summary.txt.'
    )

    initial_snapshot = snapshot_path.read_bytes()
    assert initial_snapshot.startswith(b'GNU tar-'), (
        'snapshot.snar is not a GNU tar listed-incremental snapshot.'
    )

    # Exercise backup.sh a second time. A genuine incremental archive must contain
    # a newly added file while omitting the unchanged summary file.
    token = secrets.token_hex(8)
    added_name = f'incremental_{token}.dat'
    added_path = PROCESSED / added_name
    added_path.write_text(f'new backup payload {token}\n', encoding='utf-8')

    prior_paths = {p.resolve() for p in initial_archives}
    while (BACKUP / f'backup_{int(time.time())}.tar.gz').resolve() in prior_paths:
        time.sleep(1.05)

    run_checked([str(script_path)])

    later_archives = [Path(p) for p in glob.glob(str(BACKUP / '*.tar.gz'))]
    assert len(later_archives) == 2, (
        f"Executing backup.sh once should add one archive; found {len(later_archives)} total."
    )
    for archive in later_archives:
        assert re.fullmatch(r'backup_[0-9]+\.tar\.gz', archive.name), (
            f"Backup archive has an invalid name: {archive.name}"
        )
    new_archives = [p for p in later_archives if p.resolve() not in prior_paths]
    assert len(new_archives) == 1, 'backup.sh did not create exactly one new archive.'
    incremental_members = archive_members(new_archives[0])
    assert any(name.endswith(f'dataset_processed/{added_name}') for name in incremental_members), (
        'The new incremental archive does not contain the newly added file.'
    )
    assert not any(name.endswith('dataset_processed/summary.txt') for name in incremental_members), (
        'The new archive contains an unchanged file and is not an incremental backup.'
    )
    updated_snapshot = snapshot_path.read_bytes()
    assert updated_snapshot.startswith(b'GNU tar-')
    assert updated_snapshot != initial_snapshot, 'The incremental snapshot was not updated.'

    # Check that both requested C artifacts are present and that the executable is
    # a compiled program rather than a script or fabricated text file.
    source_path = HOME / 'process_data.c'
    executable_path = HOME / 'process_data'
    assert source_path.is_file(), f"C source {source_path} is missing."
    assert executable_path.is_file(), f"Compiled executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."
    with executable_path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f"{executable_path} is not an ELF executable."

    source = source_path.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'#\s*include\s*[<\"]iconv\.h[>\"]', source), (
        'process_data.c does not include POSIX iconv.h.'
    )
    for call in ('iconv_open', 'iconv', 'iconv_close'):
        assert re.search(r'\b' + call + r'\s*\(', source), (
            f'process_data.c does not call {call}.'
        )

    # Replace the input with unpredictable filenames and values so fixed output
    # cannot pass. UTF-16LE forces actual encoding conversion, and a sentinel in
    # summary.txt verifies that results are appended rather than truncating it.
    first_name = f'latin_{secrets.token_hex(6)}.csv'
    second_name = f'wide_{secrets.token_hex(6)}.csv'
    a = secrets.randbelow(251) + 50
    b = -(secrets.randbelow(40) + 1)
    c = secrets.randbelow(401) + 100
    d = secrets.randbelow(90) + 1

    first_csv = (
        'Measurement,Label,ID\n'
        f'{a / 10:.1f},café,1\n'
        f'{b / 10:.1f},résumé,2\n'
    )
    second_csv = (
        'ID,Notes,Measurement\n'
        f'1,naïve,{c / 10:.1f}\n'
        f'2,façade,{d / 10:.1f}\n'
    )
    (RAW / first_name).write_bytes(first_csv.encode('iso-8859-1'))
    (RAW / second_name).write_bytes(second_csv.encode('utf-16le'))
    config = [
        {'filename': first_name, 'encoding': 'ISO-8859-1'},
        {'filename': second_name, 'encoding': 'UTF-16LE'},
    ]
    (RAW / 'config.json').write_text(json.dumps(config, indent=2), encoding='utf-8')

    sentinel = f'preexisting-{secrets.token_hex(5)}'
    summary_path.write_text(sentinel + '\n', encoding='utf-8')
    run_checked([str(executable_path)])

    first_sum = (Decimal(a) + Decimal(b)) / Decimal(10)
    second_sum = (Decimal(c) + Decimal(d)) / Decimal(10)
    expected_dynamic = [
        sentinel,
        f'{first_name}: {first_sum:.1f}',
        f'{second_name}: {second_sum:.1f}',
    ]
    actual_dynamic = summary_path.read_text(encoding='utf-8').splitlines()
    assert actual_dynamic == expected_dynamic, (
        f'Unexpected dynamically generated summary. Expected {expected_dynamic!r}, '
        f'got {actual_dynamic!r}.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
