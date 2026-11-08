#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_process_script_exists():
    script_path = '/home/user/process.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_malicious_paths_log():
    log_path = '/home/user/malicious_paths.log'
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_paths = ['../bad1.txt', '/etc/malicious.txt']
    assert sorted(lines) == sorted(expected_paths), f"Expected {expected_paths} in {log_path}, got {lines}."

def test_restored_files():
    restored_dir = '/home/user/restored'
    assert os.path.isdir(restored_dir), f"The output directory {restored_dir} does not exist."

    expected_files = {
        'file1.txt': "Updated data for file 1\n",
        'dir1/file2.txt': "Initial data for file 2\n",
        'dir2/file3.txt': "New file 3\n"
    }

    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(restored_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected restored file {full_path} does not exist."
        with open(full_path, 'r') as f:
            content = f.read()
        assert content == expected_content, f"Content of {full_path} is incorrect. Expected {repr(expected_content)}, got {repr(content)}."

    assert not os.path.exists(os.path.join(restored_dir, '../bad1.txt')), "Malicious file ../bad1.txt was extracted!"
    assert not os.path.exists(os.path.join(restored_dir, 'bad1.txt')), "Malicious file bad1.txt was extracted!"
    assert not os.path.exists('/etc/malicious.txt'), "Malicious file /etc/malicious.txt was extracted!"

def test_growth_log():
    log_path = '/home/user/growth.log'
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {log_path}, got {len(lines)}."

    expected_archives = ['inc_01.tar.gz', 'inc_02.tar.gz', 'inc_03.tar.gz']
    for i, line in enumerate(lines):
        match = re.match(r'^([^:]+):\s*(\d+)$', line)
        assert match, f"Line {i+1} in {log_path} is not in the correct format '<archive_filename>: <size_in_bytes>'. Got: {line}"
        archive, size = match.groups()
        assert archive == expected_archives[i], f"Expected archive {expected_archives[i]} on line {i+1}, got {archive}."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_behavior.py
import io
import os
import re
import secrets
import shutil
import stat
import subprocess
import tarfile
import tempfile
from pathlib import Path

SCRIPT = Path('/home/user/process.sh')
MALICIOUS_LOG = Path('/home/user/malicious_paths.log')
GROWTH_LOG = Path('/home/user/growth.log')

def add_file(tf, name, content):
    data = content.encode('utf-8')
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(data))

def make_archive(path, entries):
    with tarfile.open(path, 'w:gz') as tf:
        for name, content in entries:
            add_file(tf, name, content)

def du_size(path):
    output = subprocess.check_output(['du', '-sb', str(path)], text=True)
    return int(output.split('\t', 1)[0])

def test_processes_generated_archives_safely_and_computes_growth():
    token = secrets.token_hex(8)
    base = Path(tempfile.mkdtemp(prefix='process-verifier-'))
    backups = base / 'input'
    restored = base / 'output'
    model = base / 'model'
    backups.mkdir()
    model.mkdir()

    first = f'a_{token}.tar.gz'
    second = f'm_{token}.tar.gz'
    third = f'z_{token}.tar.gz'
    common = f'common_{token}.txt'
    one = f'first_{token}.txt'
    two = f'second_{token}.txt'
    three = f'third_{token}.txt'

    old_common = f'old-{token}\n'
    new_common = f'new-{token}-with-different-length\n'
    contents = {
        one: f'one-{token}\n',
        common: new_common,
        two: f'two-{token}\n',
        three: f'three-{token}\n',
    }

    relative_escape = f'../outside_{token}.txt'
    embedded_escape = f'nested/../hidden_{token}.txt'
    absolute_escape = f'/tmp/absolute_{token}.txt'
    outside_path = base / f'outside_{token}.txt'
    hidden_path = restored / f'hidden_{token}.txt'
    absolute_path = Path(absolute_escape)

    make_archive(backups / third, [(three, contents[three])])
    make_archive(backups / first, [(one, contents[one]), (common, old_common)])
    make_archive(backups / second, [
        (common, new_common),
        (relative_escape, 'relative payload\n'),
        (two, contents[two]),
        (embedded_escape, 'embedded payload\n'),
        (absolute_escape, 'absolute payload\n'),
    ])
    (backups / f'ignored_{token}.txt').write_text('not an archive\n')

    expected_sizes = []
    (model / one).write_text(contents[one])
    (model / common).write_text(old_common)
    expected_sizes.append(du_size(model))
    (model / common).write_text(new_common)
    (model / two).write_text(contents[two])
    expected_sizes.append(du_size(model))
    (model / three).write_text(contents[three])
    expected_sizes.append(du_size(model))

    for path in (MALICIOUS_LOG, GROWTH_LOG, absolute_path):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            ['bash', str(SCRIPT), str(backups), str(restored)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'process.sh exited with {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )

        assert restored.is_dir(), 'The generated restoration directory was not created.'
        for name, expected in contents.items():
            path = restored / name
            assert path.is_file(), f'Expected generated file {path} is missing.'
            assert not path.is_symlink(), f'Expected a regular file, got symlink: {path}'
            assert path.read_text() == expected, f'Incorrect content in {path}.'

        actual_files = sorted(
            str(path.relative_to(restored))
            for path in restored.rglob('*')
            if path.is_file() or path.is_symlink()
        )
        assert actual_files == sorted(contents), f'Unexpected restored entries: {actual_files}'

        assert not outside_path.exists(), f'Malicious path was extracted: {outside_path}'
        assert not hidden_path.exists(), f'Malicious embedded traversal was extracted: {hidden_path}'
        assert not absolute_path.exists(), f'Malicious absolute path was extracted: {absolute_path}'

        assert MALICIOUS_LOG.is_file(), 'malicious_paths.log was not generated.'
        malicious_lines = MALICIOUS_LOG.read_text().splitlines()
        assert malicious_lines == [relative_escape, embedded_escape, absolute_escape], (
            f'Incorrect malicious path log: {malicious_lines}'
        )

        assert GROWTH_LOG.is_file(), 'growth.log was not generated.'
        growth_lines = GROWTH_LOG.read_text().splitlines()
        expected_names = [first, second, third]
        assert len(growth_lines) == 3, f'Expected 3 growth lines, got {growth_lines}'
        for index, line in enumerate(growth_lines):
            match = re.fullmatch(r'([^:]+): (\d+)', line)
            assert match, f'Invalid growth log format: {line!r}'
            assert match.group(1) == expected_names[index], (
                f'Archives were not logged alphabetically: {growth_lines}'
            )
            assert int(match.group(2)) == expected_sizes[index], (
                f'Incorrect du -sb size for {expected_names[index]}: '
                f'expected {expected_sizes[index]}, got {match.group(2)}'
            )
    finally:
        try:
            absolute_path.unlink()
        except FileNotFoundError:
            pass
        shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
