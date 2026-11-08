#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
from pathlib import Path

PROCESSOR = Path('/home/user/processor')
SOURCE = Path('/home/user/processor.c')
PROCESSED = Path('/home/user/processed_docs')
ARCHIVE = Path('/home/user/final_docs.tar.gz')

EXPECTED = {
    'user_manual.txt_part1.txt': 'Welcome to the QuantumFlow User Manual.\nThis system is the best QuantumFlow has to offer.',
    'user_manual.txt_part2.txt': 'Chapter 2: Operation\nTo operate QuantumFlow, press the big red button.',
    'user_manual.txt_part3.txt': 'Chapter 3: Maintenance\nQuantumFlow requires daily oiling.',
    'api_guide.txt_part1.txt': 'QuantumFlow API Documentation',
    'api_guide.txt_part2.txt': 'Endpoints:\nGET /api/legacy\nReturns QuantumFlow status.',
}


def test_c_program_exists():
    assert SOURCE.is_file(), f'C source file {SOURCE} is missing.'
    assert PROCESSOR.is_file(), f'Compiled binary {PROCESSOR} is missing.'
    assert os.access(PROCESSOR, os.X_OK), f'Binary {PROCESSOR} is not executable.'
    assert PROCESSOR.read_bytes()[:4] == b'\x7fELF', 'processor must be a compiled executable.'
    subprocess.run(
        ['gcc', '-std=c11', '-Wall', '-Wextra', str(SOURCE), '-o', '/tmp/processor_from_source'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_processed_files_exist_and_content():
    assert PROCESSED.is_dir(), f'Directory {PROCESSED} is missing.'

    for filename, expected_content in EXPECTED.items():
        filepath = PROCESSED / filename
        assert filepath.is_file(), f'Expected processed file {filepath} is missing.'
        content = filepath.read_text().strip()
        assert content == expected_content, (
            f'Content mismatch in {filepath}. Expected:\n{expected_content}\nGot:\n{content}'
        )

    actual = {p.name for p in PROCESSED.iterdir()}
    assert actual == set(EXPECTED), f'processed_docs contains unexpected or missing files: {actual}'
    assert not list(PROCESSED.glob('*.tmp*')), 'Temporary output files were left behind.'


def test_draft_notes_not_processed():
    if PROCESSED.is_dir():
        for filename in os.listdir(PROCESSED):
            assert 'draft_notes' not in filename, f'Draft notes should not have been processed, found {filename}.'


def test_tar_archive():
    assert ARCHIVE.is_file(), f'Archive {ARCHIVE} is missing.'
    assert tarfile.is_tarfile(ARCHIVE), f'File {ARCHIVE} is not a valid tar archive.'

    expected_filenames = list(EXPECTED)
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        tar_members = tar.getnames()

        for expected in expected_filenames:
            found = any(expected in member for member in tar_members)
            assert found, f'Expected file {expected} not found in archive {ARCHIVE}.'

        for member in tar_members:
            assert 'draft_notes' not in member, f'Draft notes found in archive {ARCHIVE}.'

        members = tar.getmembers()
        assert all(m.isdir() or m.isfile() for m in members), 'Archive contains a non-file, non-directory member.'
        regular = [m for m in members if m.isfile()]
        archived_names = [Path(m.name).name for m in regular]
        assert len(archived_names) == len(set(archived_names)), 'Archive contains duplicate output filenames.'
        assert set(archived_names) == set(EXPECTED), (
            f'Archive contains unexpected or missing files: {archived_names}'
        )
        for member in regular:
            data = tar.extractfile(member)
            assert data is not None
            content = data.read().decode('utf-8').strip()
            assert content == EXPECTED[Path(member.name).name], (
                f'Archived content mismatch for {member.name}'
            )


def test_dynamic_execution_configuration_discovery_and_atomic_writes():
    preload_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static void record_move(const char *oldp, const char *newp) {
    const char *log = getenv("ATOMIC_LOG");
    if (!log || !oldp || !newp) return;
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    dprintf(fd, "%s\t%s\n", oldp, newp);
    close(fd);
}

int rename(const char *oldp, const char *newp) {
    static int (*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int rc = real_fn(oldp, newp);
    if (rc == 0) record_move(oldp, newp);
    return rc;
}

int renameat(int oldfd, const char *oldp, int newfd, const char *newp) {
    static int (*real_fn)(int, const char *, int, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    int rc = real_fn(oldfd, oldp, newfd, newp);
    if (rc == 0) record_move(oldp, newp);
    return rc;
}

int renameat2(int oldfd, const char *oldp, int newfd, const char *newp, unsigned flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    if (!real_fn) return -1;
    int rc = real_fn(oldfd, oldp, newfd, newp, flags);
    if (rc == 0) record_move(oldp, newp);
    return rc;
}
'''
    Path('/tmp/rename_audit.c').write_text(preload_source)
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/rename_audit.c', '-o', '/tmp/rename_audit.so', '-ldl'],
        check=True,
    )

    Path('/home/user/doc_rules.conf').write_text(
        'SEARCH=AlphaCore\nREPLACE=Nova&Flux\nDELIMITER=--DYNAMIC-CUT--\n'
    )

    legacy = Path('/home/user/legacy_docs')
    for entry in legacy.iterdir():
        if entry.is_file():
            entry.unlink()

    (legacy / 'dynamic_one.txt').write_text(
        'Status: ReadyForArchive\n'
        'AlphaCore and AlphaCore\n'
        '--DYNAMIC-CUT--\n'
        '--DYNAMIC-CUT--\n'
        'tail AlphaCore\n'
    )
    (legacy / 'without_delimiter.txt').write_text(
        'Status: ReadyForArchive\nA single AlphaCore section.\n'
    )
    (legacy / 'not_ready.txt').write_text(
        'Status: Draft\nAlphaCore must not be emitted.\n--DYNAMIC-CUT--\nignored\n'
    )
    (legacy / 'wrong_extension.md').write_text(
        'Status: ReadyForArchive\nAlphaCore must not be emitted.\n'
    )

    for entry in PROCESSED.iterdir():
        if entry.is_dir():
            subprocess.run(['rm', '-rf', str(entry)], check=True)
        else:
            entry.unlink()

    log = Path('/tmp/atomic-renames.log')
    log.unlink(missing_ok=True)
    env = os.environ.copy()
    env['LD_PRELOAD'] = '/tmp/rename_audit.so'
    env['ATOMIC_LOG'] = str(log)

    discovery_script = r'''
set -e
while IFS= read -r -d '' file; do
    first_line=$(head -n 1 -- "$file")
    if [[ "$first_line" == "Status: ReadyForArchive" ]]; then
        /home/user/processor "$file"
    fi
done < <(find /home/user/legacy_docs -maxdepth 1 -type f -name '*.txt' -print0)
'''
    subprocess.run(['bash', '-c', discovery_script], check=True, env=env, cwd='/home/user')

    dynamic_expected = {
        'dynamic_one.txt_part1.txt': 'Nova&Flux and Nova&Flux',
        'dynamic_one.txt_part2.txt': '',
        'dynamic_one.txt_part3.txt': 'tail Nova&Flux',
        'without_delimiter.txt_part1.txt': 'A single Nova&Flux section.',
    }
    actual = {p.name for p in PROCESSED.iterdir()}
    assert actual == set(dynamic_expected), f'Dynamic run produced the wrong files: {actual}'

    for name, expected in dynamic_expected.items():
        data = (PROCESSED / name).read_text().strip()
        assert data == expected, f'Dynamic content mismatch for {name}: {data!r}'
        assert 'Status: ReadyForArchive' not in data
        assert 'AlphaCore' not in data

    assert log.is_file(), 'No successful atomic rename operations were observed.'
    moves = []
    for line in log.read_text().splitlines():
        if '\t' in line:
            old, new = line.split('\t', 1)
            moves.append((old, new))

    for final_name in dynamic_expected:
        candidates = [(old, new) for old, new in moves if Path(new).name == final_name]
        assert candidates, f'{final_name} was not installed using an atomic rename.'
        assert any(old != new for old, new in candidates), f'{final_name} was not renamed from a temporary path.'

    assert not any(p.name.endswith('.tmp') or '.tmp.' in p.name for p in PROCESSED.iterdir()), (
        'Temporary files remain after processing.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
