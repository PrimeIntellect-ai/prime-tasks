#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')
INITIAL_EXPECTED = [
    'GROUP_CHECK: FAIL (eve,mallory)',
    'ROUTE_CHECK: FAIL',
    'QUOTA_CHECK: FAIL (bob,charlie)',
]


def run_checked(command, timeout=30):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def test_auditor_cpp_exists():
    file_path = '/home/user/auditor.cpp'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The C++ source code was not created.'


def test_audit_job_sh_exists():
    file_path = '/home/user/audit_job.sh'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The execution script was not created.'


def test_audit_job_executes_and_generates_artifacts():
    for path in (HOME / 'auditor', HOME / 'report.log'):
        if path.exists() or path.is_symlink():
            path.unlink()

    result = run_checked(['bash', str(HOME / 'audit_job.sh')])
    assert result.returncode == 0, f'audit_job.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}'
    assert (HOME / 'auditor').is_file(), 'audit_job.sh did not create /home/user/auditor.'
    assert os.access(HOME / 'auditor', os.X_OK), 'audit_job.sh did not create an executable auditor.'
    assert (HOME / 'report.log').is_file(), 'audit_job.sh did not create /home/user/report.log.'
    assert (HOME / 'report.log').read_text().splitlines() == INITIAL_EXPECTED


def test_auditor_binary_exists():
    file_path = '/home/user/auditor'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The C++ program was not compiled.'
    assert os.access(file_path, os.X_OK), f'File {file_path} is not executable.'


def test_report_log_content():
    file_path = '/home/user/report.log'
    assert os.path.isfile(file_path), f'File {file_path} is missing. The report log was not generated.'

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        'GROUP_CHECK: FAIL (eve,mallory)',
        'ROUTE_CHECK: FAIL',
        'QUOTA_CHECK: FAIL (bob,charlie)'
    ]

    assert len(lines) == 3, f'Expected exactly 3 lines in {file_path}, found {len(lines)}.'

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in {file_path} is incorrect. Expected: '{expected}', Got: '{lines[i]}'."


def exercise_binary(executable):
    suffix = secrets.token_hex(6)
    unauthorized = sorted([f'zeta_{suffix}', f'charlie_{suffix}', f'eve_{suffix}'])
    over_quota = sorted([f'zoe_{suffix}', f'carol_{suffix}'])

    route_header = 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n'
    default_eth0 = 'eth0\t00000000\t0102A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n'
    other_eth0 = 'eth0\t0002A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0\n'
    wlan_route = 'wlan0\t0003A8C0\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0\n'

    cases = [
        (
            'root:x:0:\nadmin:x:1001:bob,alice\nusers:x:1002:someone\n',
            route_header + default_eth0 + other_eth0,
            'alice:8000:10000\nbob:0:10000\n',
            ['GROUP_CHECK: PASS', 'ROUTE_CHECK: PASS', 'QUOTA_CHECK: PASS'],
        ),
        (
            f"admin:x:1001:alice,{unauthorized[2]},{unauthorized[0]},bob,{unauthorized[1]}\n",
            route_header + default_eth0,
            'alice:1:10\n',
            [f"GROUP_CHECK: FAIL ({','.join(unauthorized)})", 'ROUTE_CHECK: PASS', 'QUOTA_CHECK: PASS'],
        ),
        (
            'admin:x:1001:alice\n',
            route_header + other_eth0,
            'alice:80:100\n',
            ['GROUP_CHECK: PASS', 'ROUTE_CHECK: FAIL', 'QUOTA_CHECK: PASS'],
        ),
        (
            'admin:x:1001:bob\n',
            route_header + default_eth0 + wlan_route,
            'bob:4:5\n',
            ['GROUP_CHECK: PASS', 'ROUTE_CHECK: FAIL', 'QUOTA_CHECK: PASS'],
        ),
        (
            'admin:x:1001:alice,bob\n',
            route_header + default_eth0,
            f'{over_quota[1]}:9001:10000\nthreshold_{suffix}:8000:10000\n{over_quota[0]}:81:100\n',
            ['GROUP_CHECK: PASS', 'ROUTE_CHECK: PASS', f"QUOTA_CHECK: FAIL ({','.join(over_quota)})"],
        ),
    ]

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        for number, (group_data, route_data, quota_data, expected) in enumerate(cases):
            group_path = td / f'group_{number}'
            route_path = td / f'route_{number}'
            quota_path = td / f'quota_{number}'
            group_path.write_text(group_data)
            route_path.write_text(route_data)
            quota_path.write_text(quota_data)

            result = run_checked([str(executable), str(group_path), str(route_path), str(quota_path)])
            assert result.returncode == 0, f'{executable} failed on case {number}: {result.stderr}'
            assert result.stdout.splitlines() == expected, (
                f'{executable} produced incorrect output on case {number}. '
                f'Expected {expected!r}, got {result.stdout.splitlines()!r}'
            )

    for bad_args in ([], ['/tmp/a', '/tmp/b', '/tmp/c', '/tmp/d']):
        result = run_checked([str(executable), *bad_args])
        assert result.returncode != 0, f'{executable} accepted {len(bad_args)} arguments instead of exactly three.'


def test_compiled_program_handles_altered_inputs():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = Path(td) / 'auditor_from_source'
        compile_result = run_checked([
            'g++', '-std=c++17', '-o', str(rebuilt), '/home/user/auditor.cpp'
        ])
        assert compile_result.returncode == 0, f'auditor.cpp did not compile:\n{compile_result.stderr}'

        exercise_binary(rebuilt)
        exercise_binary(HOME / 'auditor')


def test_audit_job_uses_the_mock_files_and_restores_final_report():
    paths = [HOME / 'mock_group', HOME / 'mock_route', HOME / 'mock_quota']
    originals = {path: path.read_bytes() for path in paths}
    suffix = secrets.token_hex(6)
    bad_users = sorted([f'intruder_z_{suffix}', f'intruder_a_{suffix}'])
    quota_users = sorted([f'quota_z_{suffix}', f'quota_a_{suffix}'])
    expected = [
        f"GROUP_CHECK: FAIL ({','.join(bad_users)})",
        'ROUTE_CHECK: FAIL',
        f"QUOTA_CHECK: FAIL ({','.join(quota_users)})",
    ]

    try:
        paths[0].write_text(f'admin:x:1001:bob,{bad_users[0]},alice,{bad_users[1]}\n')
        paths[1].write_text(
            'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n'
            'eth0\t00000000\t0102A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n'
            'wlan0\t0003A8C0\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0\n'
        )
        paths[2].write_text(
            f'{quota_users[1]}:801:1000\n'
            f'safe_{suffix}:800:1000\n'
            f'{quota_users[0]}:9:10\n'
        )
        result = run_checked(['bash', str(HOME / 'audit_job.sh')])
        assert result.returncode == 0, f'audit_job.sh failed on altered inputs:\n{result.stderr}'
        assert (HOME / 'report.log').read_text().splitlines() == expected, (
            'audit_job.sh did not run the auditor against the altered mock files.'
        )
    finally:
        for path, content in originals.items():
            path.write_bytes(content)
        restore_result = run_checked(['bash', str(HOME / 'audit_job.sh')])
        assert restore_result.returncode == 0, f'audit_job.sh failed while restoring the final report:\n{restore_result.stderr}'

    assert (HOME / 'report.log').read_text().splitlines() == INITIAL_EXPECTED
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
