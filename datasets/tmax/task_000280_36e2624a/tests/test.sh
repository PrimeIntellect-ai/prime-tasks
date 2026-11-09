#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid
from pathlib import Path

SUMMARY = Path('/home/user/summary.csv')
SOURCE = Path('/home/user/analyzer.c')
EXECUTABLE = Path('/home/user/analyzer')
MOUNT = Path('/home/user/sys_mount')
AUDIT = Path('/home/user/audit.log')
PRELOAD = Path('/tmp/rename_probe.so')


def test_summary_csv_content():
    assert SUMMARY.is_file(), f"Expected output file {SUMMARY} does not exist."

    content = SUMMARY.read_text().strip()
    expected_lines = [
        "filepath,version",
        "/etc/app1/config.json,1.2.4",
        "/opt/app2/settings.json,2.0.1"
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {SUMMARY} does not match expected output.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def test_c_source_exists_and_uses_atomic_rename():
    assert SOURCE.is_file(), f"C source file {SOURCE} does not exist."
    content = SOURCE.read_text()
    assert re.search(r'\brename\s*\(', content), (
        "The C code does not appear to use the 'rename' function for atomic writing."
    )


def test_executable_exists():
    assert EXECUTABLE.is_file(), (
        f"Compiled executable {EXECUTABLE} does not exist. Did you compile it?"
    )
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', (
        f"{EXECUTABLE} is not a compiled executable."
    )


def build_rename_probe():
    probe_source = Path('/tmp/rename_probe.c')
    probe_source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*rename_fn)(const char *, const char *);

int rename(const char *oldpath, const char *newpath) {
    static rename_fn real_rename = NULL;
    if (!real_rename) {
        real_rename = (rename_fn)dlsym(RTLD_NEXT, "rename");
    }

    const char *log_path = getenv("ANALYZER_RENAME_LOG");
    if (log_path) {
        FILE *log = fopen(log_path, "a");
        if (log) {
            fprintf(log, "%s|%s\n", oldpath ? oldpath : "(null)",
                    newpath ? newpath : "(null)");
            fclose(log);
        }
    }
    return real_rename(oldpath, newpath);
}
''')
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-o', str(PRELOAD), str(probe_source), '-ldl'],
        text=True, capture_output=True
    )
    assert result.returncode == 0, f"Could not build rename probe: {result.stderr}"


def write_record(timestamp, filepath, action, status):
    return (
        "BEGIN RECORD\n"
        f"Timestamp: {timestamp}\n"
        f"File: {filepath}\n"
        f"Action: {action}\n"
        f"Status: {status}\n"
        "END RECORD\n"
    )


def run_dynamic_case(program, case_number):
    token = uuid.uuid4().hex
    base = f"/dynamic_{token}"
    selected_a = f"{base}/alpha/config.json"
    failed = f"{base}/ignored/failed.json"
    created = f"{base}/ignored/created.json"
    selected_b = f"{base}/nested/beta/settings.json"

    versions = {
        selected_a: f"{case_number}.{int(token[:2], 16)}.{int(token[2:4], 16)}",
        failed: f"9.{int(token[4:6], 16)}.9",
        created: f"8.{int(token[6:8], 16)}.8",
        selected_b: f"{case_number + 4}.{int(token[8:10], 16)}.{int(token[10:12], 16)}-rc1",
    }

    for logical_path, version in versions.items():
        real_path = MOUNT / logical_path.lstrip('/')
        real_path.parent.mkdir(parents=True, exist_ok=True)
        real_path.write_text(
            '{\n'
            '  "name": "runtime-generated",\n'
            f'  "version" :   "{version}",\n'
            '  "enabled": true\n'
            '}\n'
        )

    AUDIT.write_text(
        write_record(1800000000 + case_number, failed, 'MODIFIED', 'FAILED') +
        write_record(1800000010 + case_number, selected_b, 'MODIFIED', 'SUCCESS') +
        write_record(1800000020 + case_number, created, 'CREATED', 'SUCCESS') +
        write_record(1800000030 + case_number, selected_a, 'MODIFIED', 'SUCCESS')
    )

    SUMMARY.unlink(missing_ok=True)
    Path('/home/user/summary.csv.tmp').unlink(missing_ok=True)
    rename_log = Path(f'/tmp/rename_{token}.log')
    rename_log.unlink(missing_ok=True)

    env = os.environ.copy()
    env['LD_PRELOAD'] = str(PRELOAD)
    env['ANALYZER_RENAME_LOG'] = str(rename_log)
    result = subprocess.run(
        [str(program)], cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"Analyzer exited with {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert SUMMARY.is_file(), "Analyzer did not create /home/user/summary.csv."

    expected = [
        'filepath,version',
        f'{selected_b},{versions[selected_b]}',
        f'{selected_a},{versions[selected_a]}',
    ]
    actual = [line.strip() for line in SUMMARY.read_text().splitlines() if line.strip()]
    assert actual == expected, f"Dynamic output mismatch. Expected {expected}, got {actual}"
    assert not Path('/home/user/summary.csv.tmp').exists(), (
        "Temporary summary file remained after successful completion."
    )

    calls = rename_log.read_text().splitlines() if rename_log.exists() else []
    assert '/home/user/summary.csv.tmp|/home/user/summary.csv' in calls, (
        "The running analyzer did not atomically rename summary.csv.tmp to summary.csv."
    )


def test_analyzer_behavior_on_runtime_generated_inputs():
    build_rename_probe()
    run_dynamic_case(EXECUTABLE, 3)


def test_source_builds_and_implements_same_behavior():
    rebuilt = Path('/tmp/analyzer_rebuilt')
    result = subprocess.run(
        ['gcc', '-o', str(rebuilt), str(SOURCE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"analyzer.c did not compile with gcc: {result.stderr}"
    run_dynamic_case(rebuilt, 7)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
