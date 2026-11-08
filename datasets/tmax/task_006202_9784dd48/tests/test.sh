#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import secrets
import struct
import subprocess
from datetime import datetime, timezone

import pytest


def read_jsonl(path):
    records = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON found in {path}: {line}")
    return records


def test_01_parser_c_exists_and_uses_mmap():
    parser_path = '/home/user/parser.c'
    assert os.path.isfile(parser_path), f"C parser file {parser_path} is missing."
    with open(parser_path, 'r', encoding='utf-8') as f:
        content = f.read()
    assert 'mmap' in content, "The C parser must use memory-mapped I/O (mmap)."


def test_02_valid_files_moved():
    expected_files = [
        ('/home/user/organized_project/PROJ-A/2021-01/alpha.bin', 'alpha.bin'),
        ('/home/user/organized_project/PROJ-B/2021-07/beta.bin', 'beta.bin'),
        ('/home/user/organized_project/PROJ-A/2022-01/gamma.bin', 'gamma.bin'),
    ]
    for full_path, fname in expected_files:
        assert os.path.isfile(full_path), f"Valid file {fname} was not moved to the correct destination: {full_path}"


def test_03_invalid_files_remain():
    invalid_files = [
        '/home/user/raw_data/invalid/bad_magic.bin',
        '/home/user/raw_data/invalid/too_short.bin'
    ]
    for full_path in invalid_files:
        assert os.path.isfile(full_path), f"Invalid file {full_path} should remain in its original location."


def test_04_no_valid_files_in_raw_data():
    raw_data_dir = '/home/user/raw_data'
    valid_filenames = {'alpha.bin', 'beta.bin', 'gamma.bin'}
    found_valid_files = []
    for root, _, files in os.walk(raw_data_dir):
        for file in files:
            if file in valid_filenames:
                found_valid_files.append(os.path.join(root, file))
    assert not found_valid_files, f"Valid files should not remain in raw_data: {found_valid_files}"


def test_05_parsed_metrics_jsonl():
    jsonl_path = '/home/user/parsed_metrics.jsonl'
    assert os.path.isfile(jsonl_path), f"Parsed metrics file {jsonl_path} is missing."

    expected_records = {
        'alpha.bin': {'file': 'alpha.bin', 'timestamp': 1609459200, 'project': 'PROJ-A', 'metric': 123.4567},
        'beta.bin': {'file': 'beta.bin', 'timestamp': 1625097600, 'project': 'PROJ-B', 'metric': 987.6543},
        'gamma.bin': {'file': 'gamma.bin', 'timestamp': 1640995200, 'project': 'PROJ-A', 'metric': 11.1111},
    }

    parsed_records = {}
    for record in read_jsonl(jsonl_path):
        parsed_records[record.get('file')] = record

    assert len(parsed_records) == len(expected_records), f"Expected {len(expected_records)} records, found {len(parsed_records)}."
    for fname, expected in expected_records.items():
        assert fname in parsed_records, f"Record for {fname} is missing in {jsonl_path}."
        actual = parsed_records[fname]
        assert actual.get('timestamp') == expected['timestamp'], f"Incorrect timestamp for {fname}."
        assert actual.get('project') == expected['project'], f"Incorrect project for {fname}."
        assert abs(actual.get('metric', 0) - expected['metric']) < 1e-4, f"Incorrect metric value for {fname}."


def test_06_compile_and_exercise_parser_with_mmap():
    parser_src = '/home/user/parser.c'
    parser_bin = '/home/user/parser'
    build = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', parser_src, '-o', parser_bin],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert build.returncode == 0, f"parser.c did not compile:\n{build.stderr}"

    wrapper_src = '/tmp/mmap_probe.c'
    wrapper_so = '/tmp/mmap_probe.so'
    with open(wrapper_src, 'w', encoding='utf-8') as f:
        f.write(r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static void note_call(void) {
    const char *p = getenv("MMAP_PROBE_FILE");
    if (p) {
        int fd = open(p, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) { (void)write(fd, "1", 1); close(fd); }
    }
}

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    note_call();
    return real_mmap(addr, len, prot, flags, fd, off);
}

void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off64_t off) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t);
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    note_call();
    return real_mmap64(addr, len, prot, flags, fd, off);
}
''')
    probe_build = subprocess.run(
        ['gcc', '-shared', '-fPIC', wrapper_src, '-o', wrapper_so, '-ldl'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert probe_build.returncode == 0, probe_build.stderr

    case_dir = '/tmp/parser_cases'
    os.makedirs(case_dir, exist_ok=True)
    valid_cases = [
        ('one.bin', 1704067200, 'DYN-A', 42.125),
        ('two.bin', 1735689599, 'FIFTEEN-CHARS-X', -7.375),
    ]
    for fname, timestamp, project, metric in valid_cases:
        project_bytes = project.encode('ascii') + b'\0'
        project_bytes = project_bytes.ljust(16, b'\0')
        assert len(project_bytes) == 16
        path = os.path.join(case_dir, fname)
        with open(path, 'wb') as f:
            f.write(struct.pack('<II16sd', 0xC0DEFEED, timestamp, project_bytes, metric))

        probe_file = os.path.join(case_dir, fname + '.mmap')
        env = os.environ.copy()
        env['LD_PRELOAD'] = wrapper_so
        env['MMAP_PROBE_FILE'] = probe_file
        result = subprocess.run([parser_bin, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        assert result.returncode == 0, f"Parser rejected valid generated file {fname}: {result.stderr}"
        assert result.stdout == f'{timestamp}|{project}|{metric:.4f}\n', f"Unexpected parser output for {fname}: {result.stdout!r}"
        assert os.path.isfile(probe_file) and os.path.getsize(probe_file) > 0, 'The parser did not call mmap while parsing a valid file.'

    invalid_cases = {
        'short.bin': secrets.token_bytes(17),
        'wrong_magic.bin': struct.pack('<II16sd', 0x12345678, 1704067200, b'BAD\0'.ljust(16, b'\0'), 1.25),
    }
    for fname, data in invalid_cases.items():
        path = os.path.join(case_dir, fname)
        with open(path, 'wb') as f:
            f.write(data)
        result = subprocess.run([parser_bin, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 1, f"Parser must exit with code 1 for {fname}; got {result.returncode}."
        assert result.stdout == b'', f"Parser must output nothing for invalid file {fname}."


def test_07_execute_organization_script_on_unseen_files():
    script = '/home/user/organize.sh'
    assert os.path.isfile(script), f"Organization script {script} is missing."

    token = secrets.token_hex(4)
    fixture_root = os.path.join('/home/user/raw_data', 'verification_' + token, 'deep', 'nested')
    os.makedirs(fixture_root, exist_ok=True)

    generated = [
        {
            'file': f'novel_{token}_a.bin',
            'timestamp': 1675209600 + secrets.randbelow(20_000_000),
            'project': 'V' + token.upper(),
            'metric': (100000 + secrets.randbelow(800000)) / 10000.0,
        },
        {
            'file': f'novel_{token}_b.bin',
            'timestamp': 1706745600 + secrets.randbelow(20_000_000),
            'project': 'W' + token.upper(),
            'metric': (100000 + secrets.randbelow(800000)) / 10000.0,
        },
    ]

    for item in generated:
        project_bytes = (item['project'].encode('ascii') + b'\0').ljust(16, b'\0')
        path = os.path.join(fixture_root, item['file'])
        with open(path, 'wb') as f:
            f.write(struct.pack('<II16sd', 0xC0DEFEED, item['timestamp'], project_bytes, item['metric']))

    bad_magic_path = os.path.join(fixture_root, f'bad_{token}.bin')
    bad_magic_data = struct.pack('<II16sd', 0x0BADCAFE, generated[0]['timestamp'], b'INVALID\0'.ljust(16, b'\0'), 3.5)
    with open(bad_magic_path, 'wb') as f:
        f.write(bad_magic_data)

    short_path = os.path.join(fixture_root, f'short_{token}.bin')
    short_data = secrets.token_bytes(13)
    with open(short_path, 'wb') as f:
        f.write(short_data)

    result = subprocess.run(
        ['bash', script], cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"Organization script failed on generated inputs:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    assert os.path.isfile(bad_magic_path), 'The organization script moved or deleted a generated bad-magic file.'
    assert os.path.isfile(short_path), 'The organization script moved or deleted a generated short file.'
    with open(bad_magic_path, 'rb') as f:
        assert f.read() == bad_magic_data, 'The generated bad-magic file was modified.'
    with open(short_path, 'rb') as f:
        assert f.read() == short_data, 'The generated short file was modified.'

    jsonl_path = '/home/user/parsed_metrics.jsonl'
    assert os.path.isfile(jsonl_path), f"Parsed metrics file {jsonl_path} is missing after running the script."
    records = read_jsonl(jsonl_path)
    by_file = {record.get('file'): record for record in records}

    original_names = {'alpha.bin', 'beta.bin', 'gamma.bin'}
    assert original_names.issubset(by_file), 'Running the organization script removed existing metric records.'

    for item in generated:
        month = datetime.fromtimestamp(item['timestamp'], timezone.utc).strftime('%Y-%m')
        destination = os.path.join('/home/user/organized_project', item['project'], month, item['file'])
        source = os.path.join(fixture_root, item['file'])
        assert os.path.isfile(destination), f"Generated valid file was not moved to {destination}."
        assert not os.path.exists(source), f"Generated valid file remains in raw_data: {source}"
        assert item['file'] in by_file, f"JSON record missing for generated file {item['file']}."
        record = by_file[item['file']]
        assert record.get('timestamp') == item['timestamp']
        assert record.get('project') == item['project']
        assert abs(record.get('metric', 0) - item['metric']) < 1e-4
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
