#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import datetime
import glob
import os
import pathlib
import random
import secrets
import subprocess

import pytest

WORKSPACE = pathlib.Path('/home/user/workspace')
SOURCE = WORKSPACE / 'detector.c'
BINARY = pathlib.Path('/tmp/verified_detector')
HOOK_SOURCE = pathlib.Path('/tmp/pthread_hook.c')
HOOK_LIBRARY = pathlib.Path('/tmp/pthread_hook.so')


def test_workspace_exists():
    """Verify that the workspace directory was created."""
    assert os.path.isdir('/home/user/workspace'), 'Fail: /home/user/workspace directory is missing.'


@pytest.mark.parametrize('file_idx', range(4))
def test_log_files_copied(file_idx):
    """Verify that the log files were copied to the workspace."""
    log_file = f'/home/user/workspace/server_{file_idx}.log'
    assert os.path.isfile(log_file), f'Fail: Log file {log_file} is missing in workspace.'


def test_detector_c_exists():
    """Verify that the C program source file exists."""
    assert os.path.isfile('/home/user/workspace/detector.c'), 'Fail: /home/user/workspace/detector.c is missing.'


def test_anomaly_txt_correct():
    """Verify that the anomaly.txt file exists and contains the correct output."""
    anomaly_file = '/home/user/anomaly.txt'
    assert os.path.isfile(anomaly_file), f'Fail: {anomaly_file} not found.'

    with open(anomaly_file, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_content = 'ANOMALY_DETECTED: 2023-10-27 14:35'
    assert content == expected_content, f"Fail: Incorrect anomaly detected. Expected '{expected_content}', Got: '{content}'"


def test_all_archived_logs_were_actually_copied():
    archive = pathlib.Path('/home/user/log_archive')
    archived = sorted(archive.glob('*.log'))
    copied = sorted(WORKSPACE.glob('*.log'))
    assert [p.name for p in copied] == [p.name for p in archived]
    for source in archived:
        destination = WORKSPACE / source.name
        assert destination.read_bytes() == source.read_bytes(), f'{destination} is not an exact copy of {source}'


@pytest.fixture(scope='session')
def compiled_detector():
    result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-pthread', str(SOURCE), '-o', str(BINARY)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f'detector.c did not compile with pthread support:\n{result.stderr}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    return BINARY


@pytest.fixture(scope='session')
def pthread_hook():
    HOOK_SOURCE.write_text(r'''
#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*create_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg) {
    static create_fn real_create = 0;
    if (!real_create)
        real_create = (create_fn)dlsym(RTLD_NEXT, "pthread_create");
    if (!real_create)
        return -1;
    int rc = real_create(thread, attr, start_routine, arg);
    if (rc == 0) {
        const char *path = getenv("PTHREAD_COUNT_FILE");
        if (path) {
            int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (fd >= 0) {
                (void)write(fd, "1\n", 2);
                close(fd);
            }
        }
    }
    return rc;
}
''', encoding='utf-8')
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-pthread', str(HOOK_SOURCE), '-ldl', '-o', str(HOOK_LIBRARY)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return HOOK_LIBRARY


def write_utf16_log(path, records):
    lines = [f'{timestamp}|{ip}|{status}|{response}\n' for timestamp, ip, status, response in records]
    path.write_text(''.join(lines), encoding='utf-16le')


def derive_expected(paths):
    totals = collections.defaultdict(lambda: [0, 0])
    for path in paths:
        with open(path, 'r', encoding='utf-16le') as stream:
            for line in stream:
                fields = line.rstrip('\r\n').split('|')
                assert len(fields) == 4
                minute = fields[0][:16]
                totals[minute][0] += int(fields[3])
                totals[minute][1] += 1
    anomalous = sorted(minute for minute, (total, count) in totals.items() if total / count > 500)
    assert anomalous
    return f'ANOMALY_DETECTED: {anomalous[0]}'


def run_detector(binary, paths, hook=None, count_file=None):
    anomaly = pathlib.Path('/home/user/anomaly.txt')
    anomaly.unlink(missing_ok=True)
    env = os.environ.copy()
    if hook is not None:
        env['LD_PRELOAD'] = str(hook)
        env['PTHREAD_COUNT_FILE'] = str(count_file)
    result = subprocess.run(
        [str(binary), *map(str, paths)],
        cwd='/tmp',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f'detector execution failed:\nstdout: {result.stdout}\nstderr: {result.stderr}'
    assert anomaly.is_file(), 'The executed detector did not create /home/user/anomaly.txt'
    return anomaly.read_text(encoding='utf-8')


def assert_exact_line(actual, expected):
    assert actual.splitlines() == [expected], f'Expected exactly one output line {expected!r}, got {actual!r}'


def test_detector_handles_dynamic_single_utf16le_file(compiled_detector, tmp_path):
    year = secrets.randbelow(30) + 2040
    month = secrets.randbelow(10) + 1
    day = secrets.randbelow(20) + 1
    hour = secrets.randbelow(20)
    base = datetime.datetime(year, month, day, hour, 0)
    threshold_offset = secrets.randbelow(4) + 2
    records = []
    for offset in range(threshold_offset + 3):
        minute = base + datetime.timedelta(minutes=offset)
        value = secrets.randbelow(180) + 100 if offset < threshold_offset else secrets.randbelow(300) + 601
        records.append((minute.strftime('%Y-%m-%d %H:%M:%S'), '172.16.1.9', 200, value))
    random.SystemRandom().shuffle(records)
    path = tmp_path / f'dynamic_{secrets.token_hex(4)}.log'
    write_utf16_log(path, records)
    expected = derive_expected([path])
    actual = run_detector(compiled_detector, [path])
    assert_exact_line(actual, expected)


def test_detector_aggregates_files_chronologically_and_uses_pthreads(compiled_detector, pthread_hook, tmp_path):
    year = secrets.randbelow(30) + 2070
    month = secrets.randbelow(10) + 1
    day = secrets.randbelow(20) + 1
    hour = secrets.randbelow(18) + 1
    base = datetime.datetime(year, month, day, hour, 0)
    minute0 = base
    minute1 = base + datetime.timedelta(minutes=1)
    minute2 = base + datetime.timedelta(minutes=2)
    minute3 = base + datetime.timedelta(minutes=3)

    values = [
        [(minute0, 120), (minute1, 900), (minute2, 501), (minute3, 800)],
        [(minute0, 180), (minute1, 100), (minute2, 700), (minute3, 850)],
        [(minute0, 220), (minute1, 500), (minute2, 800), (minute3, 900)],
    ]
    paths = []
    for index, entries in enumerate(values):
        records = [
            ((minute + datetime.timedelta(seconds=secrets.randbelow(59))).strftime('%Y-%m-%d %H:%M:%S'),
             f'10.9.{index}.{secrets.randbelow(200) + 1}', 200, response)
            for minute, response in entries
        ]
        random.SystemRandom().shuffle(records)
        path = tmp_path / f'input_{secrets.token_hex(5)}_{index}.log'
        write_utf16_log(path, records)
        paths.append(path)

    random.SystemRandom().shuffle(paths)
    expected = derive_expected(paths)
    count_file = tmp_path / 'pthread-count.txt'
    actual = run_detector(compiled_detector, paths, pthread_hook, count_file)
    assert_exact_line(actual, expected)
    count = len(count_file.read_text(encoding='ascii').splitlines()) if count_file.exists() else 0
    assert count >= 2, f'Expected parallel log processing using POSIX threads; observed only {count} successful pthread_create call(s)'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
