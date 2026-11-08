#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile
from pathlib import Path

ARCHIVES = Path('/home/user/archives')
UNPACKED = Path('/home/user/unpacked')
RENAMED = Path('/home/user/renamed')
MASTER = Path('/home/user/final/master.csv')
HEADER_RE = re.compile(rb'^META_INFO ID: ([0-9]+) DATE: ([0-9]{4}-[0-9]{2}-[0-9]{2})$')


def archive_files():
    result = []
    for archive in sorted(ARCHIVES.glob('*.tar.gz')):
        with tarfile.open(archive, 'r:gz') as tf:
            for member in tf.getmembers():
                if not member.isfile() or not member.name.endswith('.zip'):
                    continue
                extracted = tf.extractfile(member)
                assert extracted is not None
                with tempfile.NamedTemporaryFile(suffix='.zip') as ztmp:
                    ztmp.write(extracted.read())
                    ztmp.flush()
                    with zipfile.ZipFile(ztmp.name) as zf:
                        for name in zf.namelist():
                            if not name.endswith('.txt') or name.endswith('/'):
                                continue
                            data = zf.read(name)
                            first = data.splitlines()[0] if data.splitlines() else b''
                            match = HEADER_RE.fullmatch(first)
                            assert match, f'Invalid source header in {archive}:{member.name}:{name}'
                            result.append((match.group(1).decode(), match.group(2).decode(), data))
    assert result, 'No source text files were found in the nested archives.'
    return result


def processed_lines(files):
    lines = []
    for file_id, _date, data in files:
        for raw in data.decode('utf-8').splitlines()[1:]:
            if raw.startswith('#'):
                continue
            lines.append(f"{file_id},{raw.replace('||', ',')}")
    return lines


def test_renamed_files_exist():
    """Test that the files have been extracted and renamed properly."""
    renamed_dir = "/home/user/renamed"
    assert os.path.isdir(renamed_dir), f"Directory {renamed_dir} does not exist."

    expected_files = []
    id_counter = 100
    for b in range(1, 3):
        for z in range(1, 3):
            for f in range(1, 4):
                id_counter += 1
                date_str = f"2023-01-{f:02d}"
                filename = f"data_{date_str}_{id_counter}.txt"
                expected_files.append(filename)

    actual_files = set(os.listdir(renamed_dir))
    for expected_file in expected_files:
        assert expected_file in actual_files, f"Expected renamed file {expected_file} is missing in {renamed_dir}"


def test_master_csv_contents():
    """Test that the master.csv contains the correct processed data lines."""
    master_csv_path = "/home/user/final/master.csv"
    assert os.path.isfile(master_csv_path), f"Final output file {master_csv_path} does not exist."

    expected_lines = []
    id_counter = 100
    for b in range(1, 3):
        for z in range(1, 3):
            for f in range(1, 4):
                id_counter += 1
                expected_lines.append(f"{id_counter},val{id_counter}A,val{id_counter}B,val{id_counter}C")
                expected_lines.append(f"{id_counter},val{id_counter}X,val{id_counter}Y,val{id_counter}Z")

    with open(master_csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 24, f"Expected 24 lines in master.csv, but found {len(actual_lines)}."

    expected_set = set(expected_lines)
    actual_set = set(actual_lines)

    missing_lines = expected_set - actual_set
    extra_lines = actual_set - expected_set

    assert not missing_lines, f"Missing expected lines in master.csv: {missing_lines}"
    assert not extra_lines, f"Found unexpected lines in master.csv: {extra_lines}"


def test_extraction_copies_and_processing_script():
    sources = archive_files()

    unpacked_files = [p for p in UNPACKED.rglob('*.txt') if p.is_file()]
    assert collections.Counter(p.read_bytes() for p in unpacked_files) == collections.Counter(
        data for _file_id, _date, data in sources
    ), 'The unpacked text files must be the actual files extracted from the nested archives.'

    for file_id, date, data in sources:
        target = RENAMED / f'data_{date}_{file_id}.txt'
        assert target.is_file(), f'Missing renamed copy {target.name}'
        assert target.read_bytes() == data, f'{target.name} is not an exact copy of its archived source file.'

    excluded = (ARCHIVES, UNPACKED, RENAMED, MASTER.parent)
    candidates = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or any(path == root or root in path.parents for root in excluded):
            continue
        try:
            text = path.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue
        if path.suffix != '.sh' and not re.match(r'^#![^\n]*(?:bash|sh)\b', text):
            continue
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        uses_flock = re.search(r'(^|[\s;|&(])flock(?:\s|$)', active, re.MULTILINE) is not None
        uses_parallel = (
            re.search(r'\bxargs\b[^\n]*\s-P(?:\s*[0-9]+|\s+[^\s]+)', active) is not None
            or re.search(r'(^|[\s;|&(])parallel(?:\s|$)', active, re.MULTILINE) is not None
            or re.search(r'(?<!&)&\s*$', active, re.MULTILINE) is not None
        )
        if uses_flock and uses_parallel:
            candidates.append(path)

    assert candidates, 'No Bash processing script using both parallel jobs and flock was found under /home/user.'

    token = uuid.uuid4().hex
    challenge_id = str(700000 + int(token[:5], 16) % 200000)
    challenge_date = '2041-07-19'
    challenge_data = (
        f'META_INFO ID: {challenge_id} DATE: {challenge_date}\n'
        '# verifier-generated comment\n'
        f'{token}A||{token}B||{token}C\n'
        '# another verifier-generated comment\n'
        f'{token}X||{token}Y||{token}Z\n'
    ).encode()
    challenge_path = RENAMED / f'data_{challenge_date}_{challenge_id}.txt'
    expected = collections.Counter(processed_lines(sources + [(challenge_id, challenge_date, challenge_data)]))

    original_master = MASTER.read_bytes() if MASTER.exists() else None
    backup_dir = Path(tempfile.mkdtemp(prefix='renamed_backup_'))
    backup_renamed = backup_dir / 'renamed'
    shutil.copytree(RENAMED, backup_renamed)
    errors = []
    passed = False
    try:
        for script in candidates:
            if RENAMED.exists():
                shutil.rmtree(RENAMED)
            shutil.copytree(backup_renamed, RENAMED)
            challenge_path = RENAMED / f'data_{challenge_date}_{challenge_id}.txt'
            challenge_path.write_bytes(challenge_data)
            MASTER.parent.mkdir(parents=True, exist_ok=True)
            MASTER.write_bytes(b'')
            try:
                run = subprocess.run(
                    ['bash', str(script)], cwd=str(script.parent),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
                if run.returncode != 0:
                    errors.append(f'{script}: exit status {run.returncode}: {run.stderr[-300:]}')
                    continue
                actual = collections.Counter(
                    line.strip() for line in MASTER.read_text(encoding='utf-8').splitlines() if line.strip()
                )
                if actual == expected:
                    passed = True
                    break
                errors.append(f'{script}: output did not match archived inputs plus the verifier-generated input')
            except (subprocess.TimeoutExpired, OSError, UnicodeError) as exc:
                errors.append(f'{script}: {exc}')
    finally:
        if RENAMED.exists():
            shutil.rmtree(RENAMED)
        shutil.copytree(backup_renamed, RENAMED)
        shutil.rmtree(backup_dir)
        if original_master is None:
            try:
                MASTER.unlink()
            except FileNotFoundError:
                pass
        else:
            MASTER.write_bytes(original_master)

    assert passed, 'No parallel flock-based processing script correctly processed dynamic file contents. ' + '; '.join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
