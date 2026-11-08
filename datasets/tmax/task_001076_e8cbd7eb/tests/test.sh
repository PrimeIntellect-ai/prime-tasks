#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

import pytest

DATASET = Path('/home/user/dataset')
OUTPUT = DATASET / 'output.jsonl'
ARCHIVE = DATASET / 'archive.zip'
CHECKSUM = DATASET / 'checksum.sha256'


def read_jsonl(path):
    actual_data = []
    with open(path, 'r') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f'Invalid JSON on line {line_num} in {path}: {e}')
    return actual_data


def find_processing_script():
    preferred = Path('/home/user/process_data.py')
    if preferred.is_file():
        return preferred

    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if not path.is_file():
            continue
        try:
            source = path.read_text(errors='replace')
        except OSError:
            continue
        if 'config.ini' in source and 'output.jsonl' in source:
            candidates.append(path)

    assert candidates, 'No Python processing script was found under /home/user'
    return sorted(candidates)[0]


def test_original_final_state_and_required_artifacts():
    # Preserve the original verifier's exact output assertions.
    assert OUTPUT.exists(), f'Output file not found: {OUTPUT}'
    assert OUTPUT.is_file(), f'Output path is not a file: {OUTPUT}'

    expected_data = [
        {'participant_id': 'S01', 'response_time': '450', 'accuracy': '0.95'},
        {'participant_id': 'S02', 'response_time': '510', 'accuracy': '0.88'},
        {'participant_id': 'S03', 'response_time': '480', 'accuracy': '0.92'},
    ]
    actual_data = read_jsonl(OUTPUT)
    assert len(actual_data) == len(expected_data), (
        f'Expected {len(expected_data)} lines in output.jsonl, '
        f'but found {len(actual_data)}.'
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, (
            f'Mismatch at line {i + 1} in {OUTPUT}.\n'
            f'Expected: {expected}\nGot:      {actual}'
        )

    # Verify the supplied checksum and that all archive files were extracted.
    assert ARCHIVE.is_file(), f'Archive not found: {ARCHIVE}'
    assert CHECKSUM.is_file(), f'Checksum file not found: {CHECKSUM}'
    checksum_fields = CHECKSUM.read_text().strip().split()
    assert checksum_fields, 'checksum.sha256 is empty'
    expected_digest = checksum_fields[0].lower()
    assert len(expected_digest) == 64
    int(expected_digest, 16)
    actual_digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    assert actual_digest == expected_digest, 'archive.zip does not match checksum.sha256'

    with zipfile.ZipFile(ARCHIVE) as zf:
        members = [info for info in zf.infolist() if not info.is_dir()]
        assert members, 'archive.zip contains no files'
        for info in members:
            name = info.filename[2:] if info.filename.startswith('./') else info.filename
            extracted = DATASET / name
            assert extracted.is_file(), f'Archive member was not extracted: {name}'
            assert extracted.read_bytes() == zf.read(info), (
                f'Extracted file differs from archive member: {name}'
            )

    config_path = DATASET / 'config.ini'
    assert config_path.is_file(), 'Extracted config.ini is missing'
    parser = configparser.ConfigParser()
    parser.read(config_path)
    assert parser.has_section('Headers'), 'config.ini lacks [Headers]'
    assert list(DATASET.glob('*.tsv')), 'No extracted TSV files were found'
    assert find_processing_script().is_file()


def test_script_processes_derived_inputs_and_uses_atomic_rename():
    script = find_processing_script()

    # Replace the data with a new, verifier-derived fixture. This rejects scripts
    # that merely hardcode the three original JSON objects. The matching archive
    # and checksum also allow scripts which perform extraction themselves.
    for path in DATASET.glob('*.tsv'):
        path.unlink()
    config_text = (
        '[Headers]\n'
        'raw_subject = subject_code\n'
        'latency = latency_ms\n'
        'passed = was_correct\n'
    )
    files = {
        'config.ini': config_text,
        'alpha.tsv': (
            'raw_subject\tlatency\tpassed\n'
            'Q9\t17\tyes\n'
            'Q2\t305\tno\n'
        ),
        'zeta.tsv': (
            'raw_subject\tlatency\tpassed\n'
            'R4\t81\tyes\n'
        ),
    }
    for name, content in files.items():
        (DATASET / name).write_text(content)

    with zipfile.ZipFile(ARCHIVE, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        for name, content in files.items():
            zf.writestr(name, content)
    digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    CHECKSUM.write_text(f'{digest}  archive.zip\n')
    if OUTPUT.exists():
        OUTPUT.unlink()

    # Instrument Python file opens and rename operations. A successful atomic
    # write must write a distinct temporary path and then rename/replace it onto
    # output.jsonl.
    hook_dir = Path('/tmp/verifier_hook')
    hook_dir.mkdir(exist_ok=True)
    event_log = Path('/tmp/verifier_atomic_events.log')
    event_log.unlink(missing_ok=True)
    (hook_dir / 'sitecustomize.py').write_text(r'''
import builtins
import io
import os

_LOG = '/tmp/verifier_atomic_events.log'
_orig_os_open = os.open
_orig_builtin_open = builtins.open
_orig_io_open = io.open
_orig_rename = os.rename
_orig_replace = os.replace


def _path(value):
    try:
        return os.path.abspath(os.fspath(value))
    except (TypeError, ValueError):
        return ''


def _log(kind, *values):
    line = kind + '\t' + '\t'.join(_path(v) for v in values) + '\n'
    fd = _orig_os_open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, line.encode())
    finally:
        os.close(fd)


def _builtin_open(file, mode='r', *args, **kwargs):
    if any(c in mode for c in 'wax+'):
        _log('WRITE', file)
    return _orig_builtin_open(file, mode, *args, **kwargs)


def _io_open(file, mode='r', *args, **kwargs):
    if any(c in mode for c in 'wax+'):
        _log('WRITE', file)
    return _orig_io_open(file, mode, *args, **kwargs)


def _os_open(path, flags, *args, **kwargs):
    if flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND):
        _log('WRITE', path)
    return _orig_os_open(path, flags, *args, **kwargs)


def _rename(src, dst, *args, **kwargs):
    _log('RENAME', src, dst)
    return _orig_rename(src, dst, *args, **kwargs)


def _replace(src, dst, *args, **kwargs):
    _log('RENAME', src, dst)
    return _orig_replace(src, dst, *args, **kwargs)

builtins.open = _builtin_open
io.open = _io_open
os.open = _os_open
os.rename = _rename
os.replace = _replace
''')

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = str(hook_dir) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Processing script failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.is_file(), 'Running the processing script did not create output.jsonl'

    expected = [
        {'subject_code': 'Q9', 'latency_ms': '17', 'was_correct': 'yes'},
        {'subject_code': 'Q2', 'latency_ms': '305', 'was_correct': 'no'},
        {'subject_code': 'R4', 'latency_ms': '81', 'was_correct': 'yes'},
    ]
    assert read_jsonl(OUTPUT) == expected, (
        'The processing script did not parse the changed config.ini, process all '
        'TSV files in alphabetical filename order, and map their headers correctly.'
    )

    events = event_log.read_text().splitlines() if event_log.exists() else []
    writes = set()
    atomic_rename = False
    output_abs = str(OUTPUT.resolve())
    for event in events:
        fields = event.split('\t')
        if fields[0] == 'WRITE' and len(fields) >= 2:
            writes.add(fields[1])
        elif fields[0] == 'RENAME' and len(fields) >= 3:
            src, dst = fields[1], fields[2]
            if dst == output_abs and src != dst and src in writes:
                atomic_rename = True
    assert atomic_rename, (
        'The script did not write a distinct temporary file and atomically rename '
        'or replace it as /home/user/dataset/output.jsonl'
    )

    # The atomic rename must stay on the same filesystem as the final output.
    rename_sources = []
    for event in events:
        fields = event.split('\t')
        if len(fields) >= 3 and fields[0] == 'RENAME' and fields[2] == output_abs:
            rename_sources.append(fields[1])
    assert any(Path(src).parent == OUTPUT.parent for src in rename_sources), (
        'The temporary output must be created beside output.jsonl so the final '
        'rename is atomic on the same filesystem.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
