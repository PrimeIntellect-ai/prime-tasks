#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import struct
import subprocess


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_extract_headers_source():
    src_file = '/home/user/extract_headers.c'
    assert os.path.isfile(src_file), f"C source file {src_file} does not exist."

    with open(src_file, 'r') as f:
        content = f.read()

    # Check for atomic write using rename
    assert re.search(r'\brename\s*\(', content), "The C program does not appear to use rename() for atomic writes."
    assert "inventory.csv.tmp" in content, "The C program does not reference the temporary file inventory.csv.tmp."


def test_extract_headers_executable():
    exe_file = '/home/user/extract_headers'
    assert os.path.isfile(exe_file), f"Compiled executable {exe_file} does not exist."
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable."
    with open(exe_file, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {exe_file} is not a compiled ELF executable."


def test_inventory_csv():
    inv_file = '/home/user/inventory.csv'
    assert os.path.isfile(inv_file), f"Inventory file {inv_file} does not exist."

    lines = read_nonempty_lines(inv_file)
    expected_lines = {
        "alpha.art,Alpha-Build,1,100",
        "beta.art,Beta-Core,2,250",
        "delta.art,Delta-Engine,3,500",
        "gamma.art,Gamma-Module,1,50"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, f"Contents of {inv_file} do not match expected metadata."
    assert len(lines) == len(expected_lines), f"Contents of {inv_file} contain duplicate or extra rows."


def test_final_inventory_csv():
    final_inv_file = '/home/user/final_inventory.csv'
    assert os.path.isfile(final_inv_file), f"Final inventory file {final_inv_file} does not exist."

    lines = read_nonempty_lines(final_inv_file)
    expected_lines = {
        "alpha.art,Alpha-Build,1,100",
        "gamma.art,Gamma-Module,1,50"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, f"Contents of {final_inv_file} do not match expected filtered metadata."
    assert len(lines) == len(expected_lines), f"Contents of {final_inv_file} contain duplicate or extra rows."

    inventory = read_nonempty_lines('/home/user/inventory.csv')
    deprecated = set()
    with open('/home/user/deprecated.txt', 'r') as f:
        for line in f:
            if 'DEPRECATED: ' in line:
                deprecated.add(line.split('DEPRECATED: ', 1)[1].strip())
    derived = {row for row in inventory if row.split(',', 3)[1] not in deprecated}
    assert actual_lines == derived, "Final inventory was not filtered according to deprecated.txt."


def test_backup_status():
    status_file = '/home/user/backup_status.txt'
    assert os.path.isfile(status_file), f"Backup status file {status_file} does not exist."

    with open(status_file, 'r') as f:
        content = f.read().strip()

    assert content == "CORRUPT", f"Expected backup status to be 'CORRUPT', but got '{content}'."
    archive_ok = subprocess.run(
        ['tar', '-tzf', '/home/user/backup.tar.gz'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    ).returncode == 0
    derived_status = 'OK' if archive_ok else 'CORRUPT'
    assert content == derived_status, "backup_status.txt does not reflect the archive's actual integrity."


def build_artifacts(records):
    artifact_dir = '/home/user/artifacts'
    if os.path.exists(artifact_dir):
        shutil.rmtree(artifact_dir)
    os.makedirs(artifact_dir)

    for filename, version, name, payload_size in records:
        encoded = name.encode('ascii')
        assert len(encoded) < 32
        with open(os.path.join(artifact_dir, filename), 'wb') as f:
            f.write(b'ARTF')
            f.write(struct.pack('<I', version))
            f.write(encoded + b'\0' * (32 - len(encoded)))
            f.write(struct.pack('<I', payload_size))
            f.write(os.urandom(payload_size))

    with open(os.path.join(artifact_dir, 'ignore.txt'), 'wb') as f:
        f.write(b'not an artifact')
    with open(os.path.join(artifact_dir, 'also_ignore.bin'), 'wb') as f:
        f.write(b'ARTF' + b'\0' * 40)


def make_records():
    token = secrets.token_hex(4)
    return [
        (f'new_{token}_a.art', secrets.randbelow(4000000000) + 1,
         f'Fresh-{token}-A', secrets.randbelow(80) + 1),
        (f'new_{token}_b.art', secrets.randbelow(4000000000) + 1,
         f'Fresh-{token}-B', secrets.randbelow(80) + 1),
        (f'new_{token}_c.art', secrets.randbelow(4000000000) + 1,
         f'Fresh-{token}-C', secrets.randbelow(80) + 1),
    ]


def expected_rows(records):
    return {f'{filename},{name},{version},{size}'
            for filename, version, name, size in records}


def run_and_check(program, records, preload, log_path):
    build_artifacts(records)
    for path in ('/home/user/inventory.csv', '/home/user/inventory.csv.tmp', log_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['LD_PRELOAD'] = preload
    env['RENAME_AUDIT_LOG'] = log_path
    result = subprocess.run([program], env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, (
        f'{program} failed on generated artifacts: {result.stderr.decode(errors="replace")}')
    assert os.path.isfile('/home/user/inventory.csv'), f'{program} did not create inventory.csv.'
    lines = read_nonempty_lines('/home/user/inventory.csv')
    expected = expected_rows(records)
    assert set(lines) == expected and len(lines) == len(expected), (
        f'{program} did not extract the generated artifact headers correctly.')
    assert not os.path.exists('/home/user/inventory.csv.tmp'), (
        f'{program} left inventory.csv.tmp behind after a successful run.')
    assert os.path.isfile(log_path), f'{program} did not call rename() at runtime.'
    logged = read_nonempty_lines(log_path)
    assert '/home/user/inventory.csv.tmp' in logged, (
        f'{program} did not rename the required temporary inventory file.')
    assert '/home/user/inventory.csv' in logged, (
        f'{program} did not atomically rename the temporary file to inventory.csv.')


def test_dynamic_extraction_and_atomic_rename(tmp_path):
    rebuilt = str(tmp_path / 'extract_headers_rebuilt')
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '/home/user/extract_headers.c', '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_result.returncode == 0, (
        'extract_headers.c does not compile: ' + compile_result.stderr.decode(errors='replace'))

    interceptor_src = tmp_path / 'rename_audit.c'
    interceptor_so = str(tmp_path / 'rename_audit.so')
    interceptor_src.write_text(r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

typedef int (*rename_fn)(const char *, const char *);
int rename(const char *oldpath, const char *newpath) {
    static rename_fn real_rename = NULL;
    if (!real_rename) real_rename = (rename_fn)dlsym(RTLD_NEXT, "rename");
    const char *logpath = getenv("RENAME_AUDIT_LOG");
    struct stat st;
    if (logpath && oldpath && newpath && stat(oldpath, &st) == 0) {
        FILE *f = fopen(logpath, "a");
        if (f) {
            fprintf(f, "%s\n%s\n", oldpath, newpath);
            fclose(f);
        }
    }
    return real_rename(oldpath, newpath);
}
''')
    preload_result = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(interceptor_src), '-o', interceptor_so, '-ldl'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert preload_result.returncode == 0, preload_result.stderr.decode(errors='replace')

    run_and_check('/home/user/extract_headers', make_records(), interceptor_so,
                  str(tmp_path / 'submitted_rename.log'))
    run_and_check(rebuilt, make_records(), interceptor_so,
                  str(tmp_path / 'rebuilt_rename.log'))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
