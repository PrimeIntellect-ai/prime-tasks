#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import secrets

HOME = '/home/user'
MARKER = b'ARCHIVED_2024_TECH_WRITER\n'

CANONICAL_ARCHIVE = {
    '001_intro.md': b'# Introduction\nDOC_ID: 001\nWelcome to the documentation.\n' + MARKER,
    '005_setup.md': b'# Setup Guide\nDOC_ID: 005\nHow to install.\n' + MARKER,
    '001_start_here.md': b'# Introduction\nDOC_ID: 001\nWelcome to the documentation.\n' + MARKER,
    'legacy.md': b'# Old stuff\nJust some text without an ID.\n' + MARKER,
}

EXPECTED_FILES = set(CANONICAL_ARCHIVE)
UNEXPECTED_FILES = {
    'loop1.md', 'loop2.md', 'loop3.md', 'broken_link.md', 'missing.md'
}


def assert_regular_file(path, executable=False):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f'{path} is not a regular file'
    if executable:
        assert os.access(path, os.X_OK), f'{path} is not executable'


def normalized_tar_contents(path):
    result = {}
    with tarfile.open(path, 'r:gz') as tar:
        for member in tar.getmembers():
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            if name in ('', '.'):
                assert member.isdir(), 'Non-directory archive member has an empty name'
                continue
            assert not os.path.isabs(name), f'Archive contains absolute path {member.name}'
            parts = name.split('/')
            assert '..' not in parts, f'Archive contains unsafe path {member.name}'
            assert len(parts) == 1, f'Archive member is not at archive root: {member.name}'
            assert member.isfile(), f'Archive member is not a regular file: {member.name}'
            assert name not in result, f'Duplicate archive member: {name}'
            stream = tar.extractfile(member)
            assert stream is not None
            result[name] = stream.read()
    return result


def check_final_outputs():
    archive = os.path.join(HOME, 'final_docs.tar.gz')
    assert os.path.isfile(archive), '/home/user/final_docs.tar.gz does not exist'
    assert_regular_file(archive)

    c_file = os.path.join(HOME, 'flattener.c')
    assert os.path.isfile(c_file), f'{c_file} does not exist'
    assert_regular_file(c_file)
    with open(c_file, 'r', encoding='utf-8') as f:
        content = f.read()
    assert 'rename(' in content, 'The C program does not seem to use rename() for atomic writes'

    installed = os.path.join(HOME, 'flattener')
    assert os.path.isfile(installed), f'{installed} does not exist'
    assert_regular_file(installed, executable=True)

    organizer = os.path.join(HOME, 'organizer.sh')
    assert os.path.isfile(organizer), f'{organizer} does not exist'
    assert_regular_file(organizer)

    archived = normalized_tar_contents(archive)
    extracted_files = set(archived)
    for expected in EXPECTED_FILES:
        assert expected in extracted_files, f'Expected file {expected} is missing from the archive'
    for unexpected in UNEXPECTED_FILES:
        assert unexpected not in extracted_files, f'Unexpected loop/broken file {unexpected} was found in the archive'
    assert extracted_files == EXPECTED_FILES, f'Archive has missing or extra files: {extracted_files}'

    for filename in EXPECTED_FILES:
        lines = archived[filename].decode('utf-8').splitlines()
        assert lines, f'File {filename} is empty'
        assert lines[-1] == 'ARCHIVED_2024_TECH_WRITER', \
            f'File {filename} does not end with ARCHIVED_2024_TECH_WRITER'
        assert archived[filename] == CANONICAL_ARCHIVE[filename], \
            f'Archived content of {filename} does not match its source document plus marker'

    flat = os.path.join(HOME, 'docs_flat')
    assert os.path.isdir(flat), '/home/user/docs_flat does not exist'
    flat_entries = set(os.listdir(flat))
    assert flat_entries == EXPECTED_FILES, f'docs_flat has missing or extra entries: {flat_entries}'
    for name, expected_data in CANONICAL_ARCHIVE.items():
        path = os.path.join(flat, name)
        assert_regular_file(path)
        with open(path, 'rb') as f:
            assert f.read() == expected_data, f'Incorrect content in {path}'


def build_rename_tracer(work):
    source = os.path.join(work, 'trace_rename.c')
    library = os.path.join(work, 'trace_rename.so')
    code = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

typedef int (*rename_fn)(const char *, const char *);

int rename(const char *oldpath, const char *newpath) {
    static rename_fn real_rename = NULL;
    if (!real_rename) real_rename = (rename_fn)dlsym(RTLD_NEXT, "rename");
    if (!real_rename) { errno = ENOSYS; return -1; }
    int rc = real_rename(oldpath, newpath);
    int saved_errno = errno;
    const char *logpath = getenv("TRACE_RENAME_LOG");
    if (logpath) {
        char cwd[PATH_MAX];
        char line[PATH_MAX * 3];
        if (!getcwd(cwd, sizeof(cwd))) strcpy(cwd, ".");
        int n = snprintf(line, sizeof(line), "%d\t%s\t%s\t%s\n", rc, cwd, oldpath, newpath);
        int fd = (int)syscall(SYS_openat, AT_FDCWD, logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            if (n > 0) syscall(SYS_write, fd, line, (size_t)n);
            syscall(SYS_close, fd);
        }
    }
    errno = saved_errno;
    return rc;
}
'''
    with open(source, 'w', encoding='utf-8') as f:
        f.write(code)
    subprocess.run(
        ['gcc', '-shared', '-fPIC', source, '-o', library, '-ldl'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    return library


def absolute_at_call(cwd, path):
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(cwd, path))


def exercise_flattener(binary, tracer, base):
    token = secrets.token_hex(8)
    source = os.path.join(base, 'source_' + token)
    destination = os.path.join(base, 'destination_' + token)
    os.mkdir(source)
    os.mkdir(destination)

    payloads = {
        'alpha.md': ('alpha-' + secrets.token_hex(16) + '\n').encode(),
        'beta.md': ('beta-' + secrets.token_hex(16) + '\n').encode(),
    }
    for name, data in payloads.items():
        with open(os.path.join(source, name), 'wb') as f:
            f.write(data)
    os.symlink('alpha.md', os.path.join(source, 'alias.md'))
    os.symlink('does_not_exist.md', os.path.join(source, 'broken.md'))
    os.symlink('loop_b.md', os.path.join(source, 'loop_a.md'))
    os.symlink('loop_a.md', os.path.join(source, 'loop_b.md'))
    os.mkdir(os.path.join(source, 'nested'))
    with open(os.path.join(source, 'nested', 'ignored.md'), 'wb') as f:
        f.write(b'must not be recursively copied\n')

    expected = dict(payloads)
    expected['alias.md'] = payloads['alpha.md']
    log = os.path.join(base, 'rename_' + token + '.log')
    env = os.environ.copy()
    env['LD_PRELOAD'] = tracer
    env['TRACE_RENAME_LOG'] = log
    completed = subprocess.run(
        [binary, source, destination], cwd=base, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert completed.returncode == 0, \
        f'{binary} failed with {completed.returncode}: {completed.stderr}'
    assert completed.stdout.strip(), 'Broken/loop symlinks did not produce a warning on stdout'

    actual_names = set(os.listdir(destination))
    assert actual_names == set(expected), \
        f'Flattener produced missing, invalid, recursive, or temporary files: {actual_names}'
    for name, data in expected.items():
        path = os.path.join(destination, name)
        assert_regular_file(path)
        with open(path, 'rb') as f:
            assert f.read() == data, f'Flattener changed the content of {name}'

    assert os.path.isfile(log), 'No calls to rename() were observed while copying files'
    successful = []
    with open(log, 'r', encoding='utf-8') as f:
        for line in f:
            fields = line.rstrip('\n').split('\t', 3)
            assert len(fields) == 4, 'Malformed rename trace'
            rc, cwd, old, new = fields
            if rc == '0':
                successful.append((absolute_at_call(cwd, old), absolute_at_call(cwd, new)))

    for name in expected:
        final_path = os.path.normpath(os.path.join(destination, name))
        matching = [(old, new) for old, new in successful if new == final_path]
        assert matching, f'{name} was not installed using rename()'
        for old, new in matching:
            assert old != new, f'{name} was not renamed from a temporary file'
            assert os.path.dirname(old) == os.path.normpath(destination), \
                f'Temporary file for {name} was not in the destination directory'


def check_flattener_behavior():
    with tempfile.TemporaryDirectory() as work:
        tracer = build_rename_tracer(work)
        installed = os.path.join(HOME, 'flattener')
        exercise_flattener(installed, tracer, work)

        freshly_compiled = os.path.join(work, 'flattener_from_source')
        compiled = subprocess.run(
            ['gcc', '-std=c11', os.path.join(HOME, 'flattener.c'), '-o', freshly_compiled],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert compiled.returncode == 0, f'flattener.c does not compile: {compiled.stderr}'
        exercise_flattener(freshly_compiled, tracer, work)


def append_expected(data):
    if data.endswith(b'\n'):
        return data + MARKER
    return data + b'\n' + MARKER


def check_organizer_behavior():
    flat = os.path.join(HOME, 'docs_flat')
    archive = os.path.join(HOME, 'final_docs.tar.gz')
    with tempfile.TemporaryDirectory() as backup:
        flat_backup = os.path.join(backup, 'docs_flat')
        archive_backup = os.path.join(backup, 'final_docs.tar.gz')
        shutil.copytree(flat, flat_backup, symlinks=True)
        archive_existed = os.path.lexists(archive)
        if archive_existed:
            shutil.copy2(archive, archive_backup)

        try:
            shutil.rmtree(flat)
            os.mkdir(flat)
            token = secrets.token_hex(5)
            doc_id_a = str(secrets.randbelow(800) + 100)
            doc_id_b = str(secrets.randbelow(800) + 100)
            inputs = {
                f'alpha_{token}.md': f'# Random alpha {token}\nDOC_ID: {doc_id_a}\nbody {secrets.token_hex(12)}\n'.encode(),
                f'multi.part_{token}.md': f'DOC_ID: {doc_id_b}\nsecond {secrets.token_hex(12)}\n'.encode(),
                f'noid_{token}.md': f'No identifier here\n{secrets.token_hex(12)}\n'.encode(),
            }
            for name, data in inputs.items():
                with open(os.path.join(flat, name), 'wb') as f:
                    f.write(data)

            completed = subprocess.run(
                ['/bin/bash', os.path.join(HOME, 'organizer.sh')], cwd=HOME,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
            )
            assert completed.returncode == 0, \
                f'organizer.sh failed with {completed.returncode}: {completed.stderr}'

            expected = {
                f'{doc_id_a}_alpha_{token}.md': append_expected(inputs[f'alpha_{token}.md']),
                f'{doc_id_b}_multi.part_{token}.md': append_expected(inputs[f'multi.part_{token}.md']),
                f'noid_{token}.md': append_expected(inputs[f'noid_{token}.md']),
            }
            actual = set(os.listdir(flat))
            assert actual == set(expected), f'organizer.sh produced incorrect filenames: {actual}'
            for name, data in expected.items():
                path = os.path.join(flat, name)
                assert_regular_file(path)
                with open(path, 'rb') as f:
                    assert f.read() == data, f'organizer.sh produced incorrect content in {name}'
        finally:
            if os.path.lexists(flat):
                if os.path.isdir(flat) and not os.path.islink(flat):
                    shutil.rmtree(flat)
                else:
                    os.unlink(flat)
            shutil.copytree(flat_backup, flat, symlinks=True)
            if os.path.lexists(archive):
                os.unlink(archive)
            if archive_existed:
                shutil.copy2(archive_backup, archive)


def test_complete_workflow():
    check_final_outputs()
    check_flattener_behavior()
    check_organizer_behavior()
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
