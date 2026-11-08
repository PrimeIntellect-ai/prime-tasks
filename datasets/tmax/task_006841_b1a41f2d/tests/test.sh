#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess


def test_result_txt():
    """Test that result.txt exists and contains the required original result."""
    result_path = '/home/user/result.txt'
    assert os.path.isfile(result_path), f"{result_path} is missing. Did you redirect the output?"
    with open(result_path, 'r') as f:
        content = f.read().strip()
    assert content == "1000", f"Expected output to be '1000', but got '{content}'."


def test_check_backup_c_parameterization():
    """Test that check_backup.c uses a parameterized SQLite query."""
    c_file_path = '/home/user/check_backup.c'
    assert os.path.isfile(c_file_path), f"{c_file_path} is missing."
    with open(c_file_path, 'r') as f:
        content = f.read()

    assert "sqlite3_bind" in content, "The C program must use sqlite3_bind_* to parameterize the query."
    assert "%s" not in content, "The C program still appears to use string interpolation (%s) for the query."

    # Ignore comments when checking that bind is an actual function call rather
    # than a keyword placed only in a comment.
    without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', content, flags=re.S)
    assert re.search(r'\bsqlite3_bind_(?:int|int64|text|value|double|blob|null)\s*\(', without_comments), \
        "No SQLite bind function call was found in the C program."
    assert '?' in without_comments, "The SQL must contain a parameter placeholder."


def test_executable_exists():
    """Test that the compiled executable exists and is an ELF binary."""
    exe_path = '/home/user/check_backup'
    assert os.path.isfile(exe_path), f"{exe_path} is missing. Did you compile the program?"
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."
    with open(exe_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "check_backup must be a compiled executable."


def _run_and_read_integer(executable, argument):
    proc = subprocess.run(
        [executable, str(argument)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert proc.returncode == 0, \
        f"{executable} exited with {proc.returncode}: {proc.stderr}"
    assert re.fullmatch(r'\s*-?\d+\s*', proc.stdout), \
        f"Expected a single integer from {executable}, got {proc.stdout!r}"
    return int(proc.stdout.strip())


def _check_injection_is_not_executed(executable, root_id, expected_root):
    proc = subprocess.run(
        [executable, f'{root_id} OR 1=1'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    # Rejecting malformed input is safe. Binding it as text may produce 0,
    # while sqlite3_bind_int commonly parses the leading integer.
    if proc.returncode != 0:
        return
    assert re.fullmatch(r'\s*-?\d+\s*', proc.stdout), \
        f"Expected an integer or rejection for injection-like input, got {proc.stdout!r}"
    value = int(proc.stdout.strip())
    assert value in (0, expected_root), \
        "Injection-like input changed SQL semantics; the directory ID was not safely bound."


def test_program_behavior_on_generated_database():
    """Compile the submitted source and exercise both it and the submitted binary."""
    source_binary = '/tmp/check_backup_from_source'
    build = subprocess.run(
        ['/usr/bin/gcc', '-o', source_binary, '/home/user/check_backup.c', '-lsqlite3'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"check_backup.c does not compile: {build.stderr}"

    db_path = '/home/user/backup_meta.db'
    backup_path = '/tmp/backup_meta.db.verifier-backup'
    shutil.copy2(db_path, backup_path)

    base = 10000 + secrets.randbelow(500000)
    root = base
    subdir = base + 2
    nested_dir = base + 4
    other_root = base + 100
    a = 20 + secrets.randbelow(5000)
    b = 20 + secrets.randbelow(5000)
    c = 20 + secrets.randbelow(5000)
    d = 10000 + secrets.randbelow(5000)

    rows = [
        (root, None, 'generated-root', '{"type":"dir","size":0}'),
        (base + 1, root, 'first-file', f'{{"type":"file","size":{a}}}'),
        (subdir, root, 'generated-subdir', '{"type":"dir","size":0}'),
        (base + 3, subdir, 'deep-file', f'{{"type":"file","size":{b}}}'),
        (nested_dir, subdir, 'nested-dir', '{"type":"dir","size":0}'),
        (base + 5, nested_dir, 'deeper-file', f'{{"type":"file","size":{c}}}'),
        (other_root, None, 'unrelated-root', '{"type":"dir","size":0}'),
        (base + 101, other_root, 'unrelated-file', f'{{"type":"file","size":{d}}}'),
    ]

    try:
        for suffix in ('-wal', '-shm', '-journal'):
            try:
                os.remove(db_path + suffix)
            except FileNotFoundError:
                pass
        os.remove(db_path)
        conn = sqlite3.connect(db_path)
        conn.execute('CREATE TABLE files(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, metadata TEXT)')
        conn.executemany('INSERT INTO files VALUES (?, ?, ?, ?)', rows)
        conn.commit()
        conn.close()

        expected = {
            root: a + b + c,
            subdir: b + c,
            nested_dir: c,
            other_root: d,
        }
        for executable in ('/home/user/check_backup', source_binary):
            for directory_id, total in expected.items():
                actual = _run_and_read_integer(executable, directory_id)
                assert actual == total, \
                    f"{executable} returned {actual} for directory {directory_id}; expected {total}"
            _check_injection_is_not_executed(executable, root, expected[root])
    finally:
        for suffix in ('-wal', '-shm', '-journal'):
            try:
                os.remove(db_path + suffix)
            except FileNotFoundError:
                pass
        shutil.move(backup_path, db_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
