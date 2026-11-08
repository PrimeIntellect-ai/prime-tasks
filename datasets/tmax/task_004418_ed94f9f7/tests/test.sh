#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import io
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import zipfile

MASTER = '/home/user/master_output.json'
DUMMY = {"id": "999", "project_name": "final_check", "status": "completed"}


def archive_contents():
    zips = {}
    csvs = {}
    with tarfile.open('/home/user/legacy_assets.tar.gz', 'r:gz') as outer:
        for member in outer.getmembers():
            if member.isfile() and member.name.lower().endswith('.zip'):
                data = outer.extractfile(member).read()
                name = os.path.basename(member.name)
                assert name not in zips
                zips[name] = data
                with zipfile.ZipFile(io.BytesIO(data)) as zf:
                    for csv_name in zf.namelist():
                        if not csv_name.endswith('/') and csv_name.lower().endswith('.csv'):
                            base = os.path.basename(csv_name)
                            assert base not in csvs, f"Duplicate CSV basename in source archive: {base}"
                            csvs[base] = zf.read(csv_name)
    return zips, csvs


def expected_records():
    _, csvs = archive_contents()
    result = []
    for data in csvs.values():
        for raw in data.decode('utf-8').splitlines():
            if not raw:
                continue
            fields = raw.split(',')
            assert len(fields) == 3
            result.append({"id": fields[0], "project_name": fields[1], "status": fields[2]})
    return result


def record_counter(records):
    return collections.Counter(
        (r.get('id'), r.get('project_name'), r.get('status'), tuple(sorted(r.keys())))
        for r in records
    )


def read_json_lines(path):
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
    records = []
    for i, line in enumerate(lines):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {path} is not valid JSON: {line}"
        assert isinstance(value, dict), f"Line {i+1} in {path} is not a JSON object"
        records.append(value)
    return lines, records


def archive_json(archive_path):
    with tarfile.open(archive_path, 'r') as tar:
        members = tar.getnames()
        master_member = [m for m in members if m.endswith('master_output.json')]
        assert master_member, f"master_output.json not found in {archive_path}."
        assert len(master_member) == 1, f"Multiple master_output.json entries in {archive_path}."
        extracted = tar.extractfile(master_member[0])
        assert extracted is not None
        text = extracted.read().decode('utf-8')
    lines = text.splitlines()
    records = []
    for i, line in enumerate(lines):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} in {archive_path} is not valid JSON: {line}"
        assert isinstance(value, dict)
        records.append(value)
    return lines, records


def test_extraction_is_complete_and_correct():
    expected_zips, expected_csvs = archive_contents()

    found_zips = {}
    for root, _, files in os.walk('/home/user/assets_extracted'):
        for name in files:
            if name.lower().endswith('.zip'):
                assert name not in found_zips, f"Duplicate extracted zip basename: {name}"
                with open(os.path.join(root, name), 'rb') as f:
                    found_zips[name] = f.read()
    assert found_zips == expected_zips, "Extracted zip files do not match the nested source archive"

    found_csvs = {}
    for root, _, files in os.walk('/home/user/csv_data'):
        for name in files:
            if name.lower().endswith('.csv'):
                assert name not in found_csvs, f"Duplicate extracted CSV basename: {name}"
                with open(os.path.join(root, name), 'rb') as f:
                    found_csvs[name] = f.read()
    assert found_csvs == expected_csvs, "csv_data does not contain exactly the CSV files from all nested zips"


def test_master_output_exists_and_content():
    assert os.path.exists(MASTER), f"File {MASTER} does not exist."
    lines, records = read_json_lines(MASTER)
    assert len(lines) == 11, f"Expected 11 lines in {MASTER}, found {len(lines)}."

    expected_apollo = {"id": "101", "project_name": "Apollo", "status": "active"}
    expected_dummy = DUMMY
    assert expected_apollo in records, f"Record {expected_apollo} not found in {MASTER}."
    assert expected_dummy in records, f"Dummy record {expected_dummy} not found in {MASTER}."

    expected = expected_records() + [DUMMY]
    assert record_counter(records) == record_counter(expected), \
        "Master output does not contain exactly the records derived from the archived CSV files plus the dummy record"


def test_backup_level0():
    backup0_path = '/home/user/backup_level0.tar'
    assert os.path.exists(backup0_path), f"Backup file {backup0_path} does not exist."
    lines, records = archive_json(backup0_path)
    assert len(lines) == 10, f"Expected 10 lines in Level 0 backup of master_output.json, found {len(lines)}."
    for record in records:
        assert record.get('id') != '999', \
            "Dummy record found in Level 0 backup, which should only have 10 original records."
    assert record_counter(records) == record_counter(expected_records()), \
        "Level 0 backup is not an exact snapshot of the ten source CSV records"


def test_backup_level1():
    backup1_path = '/home/user/backup_level1.tar'
    assert os.path.exists(backup1_path), f"Backup file {backup1_path} does not exist."
    lines, records = archive_json(backup1_path)
    assert len(lines) == 11, f"Expected 11 lines in Level 1 backup of master_output.json, found {len(lines)}."
    dummy_found = any(record.get('id') == '999' for record in records)
    assert dummy_found, "Dummy record not found in Level 1 backup."
    assert record_counter(records) == record_counter(expected_records() + [DUMMY]), \
        "Level 1 backup is not an exact snapshot after appending the dummy record"


def test_incremental_snapshot_exists_and_is_gnu_tar_metadata():
    path = '/home/user/backup.snar'
    assert os.path.isfile(path), f"Snapshot file {path} does not exist."
    assert os.path.getsize(path) > 0, f"Snapshot file {path} is empty."
    with open(path, 'rb') as f:
        header = f.read(32)
    assert header.startswith(b'GNU tar-'), f"{path} is not a GNU tar incremental snapshot file"


def test_c_program_compiled_without_warnings():
    c_source = '/home/user/transformer.c'
    c_bin = '/home/user/transformer'
    assert os.path.exists(c_source), f"C source file {c_source} does not exist."
    assert os.path.exists(c_bin), f"Compiled binary {c_bin} does not exist."
    assert os.access(c_bin, os.X_OK), f"Compiled binary {c_bin} is not executable."
    with open(c_bin, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{c_bin} is not an ELF executable"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'transformer')
        result = subprocess.run(
            ['gcc', '-Wall', '-Wextra', '-Werror', c_source, '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
        assert result.returncode == 0, \
            f"transformer.c does not compile cleanly with warnings treated as errors:\n{result.stderr}"


def run_lock_check(binary, csv_path):
    with open(MASTER, 'a+', encoding='utf-8') as locked:
        locked.seek(0)
        fcntl.lockf(locked.fileno(), fcntl.LOCK_EX)
        fcntl.flock(locked.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen([binary, csv_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(0.5)
        assert proc.poll() is None, \
            "Transformer did not wait while master_output.json was held under exclusive POSIX locks"
        locked.seek(0)
        assert locked.read() == '', "Transformer wrote to the master file before obtaining the exclusive lock"
        fcntl.flock(locked.fileno(), fcntl.LOCK_UN)
        fcntl.lockf(locked.fileno(), fcntl.LOCK_UN)
    out, err = proc.communicate(timeout=5)
    assert proc.returncode == 0, f"Transformer failed after the lock was released: {out}\n{err}"


def test_transformer_behavior_locking_and_concurrency():
    source = '/home/user/transformer.c'
    submitted_binary = '/home/user/transformer'
    with open(source, 'r', encoding='utf-8', errors='replace') as f:
        source_text = f.read()
    assert re.search(r'\b(flock|fcntl)\s*\(', source_text), \
        "transformer.c does not call flock() or fcntl()"
    assert ('LOCK_EX' in source_text or 'F_WRLCK' in source_text), \
        "transformer.c does not request an exclusive/write lock"

    saved = None
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'rebuilt_transformer')
        result = subprocess.run(
            ['gcc', '-Wall', '-Wextra', '-Werror', source, '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
        assert result.returncode == 0, result.stderr

        saved = os.path.join(td, 'original_master.json')
        os.replace(MASTER, saved)
        try:
            open(MASTER, 'w').close()
            lock_csv = os.path.join(td, 'lock_input.csv')
            with open(lock_csv, 'w', encoding='utf-8') as f:
                f.write('7001,lock_probe,waiting\n')
            run_lock_check(submitted_binary, lock_csv)
            _, lock_records = read_json_lines(MASTER)
            assert lock_records == [{"id": "7001", "project_name": "lock_probe", "status": "waiting"}], \
                "Submitted executable did not transform the lock-probe CSV correctly"

            open(MASTER, 'w').close()
            input_dir = os.path.join(td, 'inputs')
            os.mkdir(input_dir)
            expected = []
            for file_no in range(12):
                path = os.path.join(input_dir, f'input_{file_no}.csv')
                with open(path, 'w', encoding='utf-8') as f:
                    for row_no in range(80):
                        rec = {
                            "id": str(800000 + file_no * 100 + row_no),
                            "project_name": f"project_{file_no}_{row_no}",
                            "status": ['active', 'paused', 'completed'][row_no % 3],
                        }
                        expected.append(rec)
                        f.write(f"{rec['id']},{rec['project_name']},{rec['status']}\n")

            command = f"find {input_dir} -type f -name '*.csv' | xargs -P 4 -n 1 {rebuilt}"
            run = subprocess.run(['bash', '-c', command], stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True, timeout=30)
            assert run.returncode == 0, f"Concurrent xargs execution failed: {run.stderr}"
            lines, actual = read_json_lines(MASTER)
            assert len(lines) == len(expected), \
                f"Concurrent transformer run produced {len(lines)} records instead of {len(expected)}"
            assert record_counter(actual) == record_counter(expected), \
                "Concurrent transformer output is missing, duplicated, fabricated, or corrupted"
        finally:
            try:
                os.remove(MASTER)
            except FileNotFoundError:
                pass
            if saved is not None and os.path.exists(saved):
                os.replace(saved, MASTER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
