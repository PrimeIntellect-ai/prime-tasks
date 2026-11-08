#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
import pathlib
import shutil
import stat
import struct
import subprocess
import tempfile
import uuid

HOME = pathlib.Path('/home/user')
RAW = HOME / 'dataset/raw'
BACKUP = HOME / 'dataset/backup'
MANIFEST = BACKUP / 'manifest.jsonl'
EXTRACTOR = HOME / 'extractor'
SOURCE = HOME / 'extractor.c'
SCRIPT = HOME / 'backup.sh'

CSV_DATA = {
    'data1.dat': 'record_id,sensor_value,status\n1,10.5,ok\n2,12.5,ok\n',
    'data2.dat': 'record_id,sensor_value,status\n1,5.0,ok\n2,7.0,ok\n3,3.0,err\n',
    'data3.dat': 'record_id,sensor_value,status\n1,20.0,ok\n2,30.0,ok\n',
    'data4.dat': 'record_id,sensor_value,status\n1,100.1,ok\n2,200.2,ok\n',
}
TIMESTAMPS = {
    'data1.dat': 1600000000,
    'data2.dat': 1600000100,
    'data3.dat': 1600000200,
    'data4.dat': 1600000300,
}
AVERAGES = {
    'data1.dat': 11.50,
    'data2.dat': 5.00,
    'data3.dat': 25.00,
    'data4.dat': 150.15,
}

def expected_bytes(name):
    return struct.pack('<4sIHH', b'RSCH', TIMESTAMPS[name], 1, 12) + CSV_DATA[name].encode()

def read_manifest():
    assert MANIFEST.is_file(), f'Manifest file {MANIFEST} is missing.'
    lines = [line.strip() for line in MANIFEST.read_text().splitlines() if line.strip()]
    records = []
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f'Line {i+1} in manifest is not valid JSON: {line}'
        assert isinstance(record, dict), f'Line {i+1} is not a JSON object.'
        assert 'file' in record, f"Record missing 'file' key: {line}"
        records.append(record)
    return lines, records

def assert_extractor_output(program, path, timestamp, average):
    result = subprocess.run([str(program), str(path)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert result.stderr == '', f'Extractor wrote to stderr: {result.stderr!r}'
    assert result.stdout.endswith('\n') and result.stdout.count('\n') == 1, \
        f'Extractor must print exactly one line, got {result.stdout!r}'
    try:
        record = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        assert False, f'Extractor output is not valid JSON: {exc}: {result.stdout!r}'
    assert isinstance(record, dict)
    assert set(record) == {'file', 'sha256', 'timestamp', 'avg'}, record
    assert record['file'] == path.name
    assert record['sha256'] == hashlib.sha256(path.read_bytes()).hexdigest()
    assert record['timestamp'] == timestamp
    assert isinstance(record['avg'], (int, float)) and not isinstance(record['avg'], bool)
    assert float(record['avg']) == average
    return result.stdout.rstrip('\n')

def test_backup_files_exist():
    expected_files = [
        '/home/user/dataset/backup/data1.dat',
        '/home/user/dataset/backup/data2.dat',
        '/home/user/dataset/backup/data3.dat',
        '/home/user/dataset/backup/data4.dat',
    ]
    for f in expected_files:
        assert os.path.isfile(f), f'Expected backed up file {f} is missing.'


def test_manifest_content_and_copied_bytes():
    lines, record_list = read_manifest()
    assert len(lines) == 4, f'Manifest should contain exactly 4 lines, found {len(lines)}.'

    records = {}
    for record in record_list:
        assert record['file'] not in records, f"Duplicate manifest record for {record['file']}"
        records[record['file']] = record

    expected_files = ['data1.dat', 'data2.dat', 'data3.dat', 'data4.dat']
    for ef in expected_files:
        assert ef in records, f'Manifest is missing record for {ef}.'
        content = expected_bytes(ef)
        backup_path = BACKUP / ef
        assert backup_path.read_bytes() == content, f'Backed-up contents for {ef} are incorrect.'
        record = records[ef]
        assert set(record) == {'file', 'sha256', 'timestamp', 'avg'}, record
        assert record['sha256'] == hashlib.sha256(content).hexdigest()
        assert record['timestamp'] == TIMESTAMPS[ef]
        assert float(record['avg']) == AVERAGES[ef]

    assert (RAW / 'data1.dat').read_bytes() == expected_bytes('data1.dat')
    assert (RAW / 'data3.dat').read_bytes() == expected_bytes('data3.dat')
    assert (RAW / 'data4.dat').read_bytes() == expected_bytes('data4.dat')

    # Preserve the original verifier's explicit assertions.
    data3 = records['data3.dat']
    assert data3.get('timestamp') == 1600000200
    assert float(data3.get('avg')) == 25.0
    data4 = records['data4.dat']
    assert data4.get('timestamp') == 1600000300
    assert float(data4.get('avg')) == 150.15


def test_extractor_source_and_compiled_program():
    assert SOURCE.is_file(), '/home/user/extractor.c is missing.'
    assert EXTRACTOR.is_file(), '/home/user/extractor is missing.'
    assert os.access(EXTRACTOR, os.X_OK), '/home/user/extractor is not executable.'
    assert EXTRACTOR.read_bytes()[:4] == b'\x7fELF', 'extractor is not a compiled ELF program.'

    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        rebuilt = td / 'extractor-rebuilt'
        build = subprocess.run(
            ['gcc', str(SOURCE), '-o', str(rebuilt), '-lcrypto'],
            capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f'extractor.c does not compile:\n{build.stderr}'

        probe1 = td / 'independent_a.dat'
        payload1 = 'record_id,sensor_value,status\n1,10.0,ok\n2,20.0,ok\n3,31.0,err\n'
        probe1.write_bytes(struct.pack('<4sIHH', b'RSCH', 287454020, 7, 12) + payload1.encode())

        probe2 = td / 'independent_b.dat'
        payload2 = 'record_id,sensor_value,status\n9,-2.5,ok\n10,5.5,ok\n'
        probe2.write_bytes(struct.pack('<4sIHH', b'RSCH', 4000000001, 2, 12) + payload2.encode())

        for program in (EXTRACTOR, rebuilt):
            assert_extractor_output(program, probe1, 287454020, 20.33)
            assert_extractor_output(program, probe2, 4000000001, 1.50)


def test_backup_script_incremental_behavior_and_extractor_use():
    assert SCRIPT.is_file(), '/home/user/backup.sh is missing.'
    assert os.access(SCRIPT, os.X_OK), '/home/user/backup.sh is not executable.'
    syntax = subprocess.run(['bash', '-n', str(SCRIPT)], capture_output=True, text=True, timeout=10)
    assert syntax.returncode == 0, syntax.stderr

    token = 'verifier_' + uuid.uuid4().hex
    first_name = token + '_new.dat'
    duplicate_name = token + '_duplicate.dat'
    first_raw = RAW / first_name
    duplicate_raw = RAW / duplicate_name
    first_backup = BACKUP / first_name
    duplicate_backup = BACKUP / duplicate_name
    original_manifest = MANIFEST.read_bytes()

    timestamp = 3456789012
    payload = 'record_id,sensor_value,status\n101,4.25,ok\n102,8.75,ok\n103,12.0,err\n'
    content = struct.pack('<4sIHH', b'RSCH', timestamp, 9, 12) + payload.encode()
    expected_hash = hashlib.sha256(content).hexdigest()
    expected_avg = 8.33

    real_extractor = pathlib.Path('/tmp') / (token + '_real_extractor')
    call_log = pathlib.Path('/tmp') / (token + '_calls')
    moved = False
    try:
        first_raw.write_bytes(content)

        # Interpose a transparent logger at the required extractor path. This
        # verifies that backup.sh actually invokes the compiled extractor.
        os.replace(EXTRACTOR, real_extractor)
        moved = True
        EXTRACTOR.write_text(
            '#!/bin/bash\n'
            + 'printf "%s\\n" "$1" >> ' + json.dumps(str(call_log)) + '\n'
            + 'exec ' + json.dumps(str(real_extractor)) + ' "$@"\n'
        )
        EXTRACTOR.chmod(0o755)

        run1 = subprocess.run([str(SCRIPT)], cwd=str(HOME), capture_output=True, text=True, timeout=30)
        assert run1.returncode == 0, f'backup.sh failed: stdout={run1.stdout!r} stderr={run1.stderr!r}'
        assert first_backup.is_file(), 'New raw file was not copied to backup.'
        assert first_backup.read_bytes() == content, 'Copied backup differs from the raw file.'

        calls = call_log.read_text().splitlines() if call_log.exists() else []
        assert str(first_raw) in calls, 'backup.sh did not process the new file with /home/user/extractor.'

        after_lines, after_records = read_manifest()
        assert len(after_lines) == 5, 'Exactly one manifest record should be appended for a new checksum.'
        assert MANIFEST.read_bytes().startswith(original_manifest), 'Existing manifest records were modified.'
        new_records = [r for r in after_records if r.get('file') == first_name]
        assert len(new_records) == 1
        record = new_records[0]
        assert set(record) == {'file', 'sha256', 'timestamp', 'avg'}
        assert record['sha256'] == expected_hash
        assert record['timestamp'] == timestamp
        assert float(record['avg']) == expected_avg

        stable_manifest = MANIFEST.read_bytes()
        os.utime(first_backup, (1234567890, 1234567890))
        stable_stat = first_backup.stat()

        # Running again with the same file must neither append nor recopy it.
        run2 = subprocess.run([str(SCRIPT)], cwd=str(HOME), capture_output=True, text=True, timeout=30)
        assert run2.returncode == 0, run2.stderr
        assert MANIFEST.read_bytes() == stable_manifest, 'Unchanged checksum was appended again.'
        now_stat = first_backup.stat()
        assert now_stat.st_mtime_ns == stable_stat.st_mtime_ns, 'Existing backup was recopied instead of skipped.'
        assert first_backup.read_bytes() == content

        # A different basename with a checksum already anywhere in the manifest
        # must also be skipped completely.
        duplicate_raw.write_bytes(content)
        run3 = subprocess.run([str(SCRIPT)], cwd=str(HOME), capture_output=True, text=True, timeout=30)
        assert run3.returncode == 0, run3.stderr
        assert MANIFEST.read_bytes() == stable_manifest, 'Duplicate checksum produced another manifest record.'
        assert not duplicate_backup.exists(), 'Duplicate checksum under another name was copied.'
    finally:
        for path in (first_raw, duplicate_raw, first_backup, duplicate_backup):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        MANIFEST.write_bytes(original_manifest)
        if moved:
            try:
                EXTRACTOR.unlink()
            except FileNotFoundError:
                pass
            if real_extractor.exists():
                os.replace(real_extractor, EXTRACTOR)
        try:
            call_log.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
