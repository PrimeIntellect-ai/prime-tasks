#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid
from pathlib import Path

import pytest

HOME = Path('/home/user')
SERVERS = HOME / 'servers.csv'
CHANGES = HOME / 'changes.csv'
REPORTS = HOME / 'reports'
SCRIPT = HOME / 'run_pipeline.sh'
SOURCE = HOME / 'process_configs.cpp'
BINARY = HOME / 'process_configs'

ORIGINAL_SERVERS = """ServerID,Region,IPAddress,OwnerEmail
S1,US-East,10.0.0.15,admin1@company.com
S2,EU-West,192.168.100.22,sysop_eu@company.com
S3,US-West,172.16.5.99,devops@internal.net
"""

ORIGINAL_CHANGES = """ServerID,Timestamp,UserID,ConfigKey,NewValue
S1,2023-10-01T10:00:00Z,U98765,MaxConnections,100
S2,2023-10-01T11:00:00Z,U12345,Timeout,30
S1,2023-10-02T09:00:00Z,U98765,Port,8080
S3,2023-10-03T08:15:00Z,A0001Z,LogLevel,DEBUG
S2,2023-10-04T14:20:00Z,U12345,SSL,true
"""


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed ({result.returncode}): {command}\n{result.stdout}"
    return result


def clear_reports():
    if REPORTS.exists():
        assert REPORTS.is_dir(), f"Reports path is not a directory: {REPORTS}"
        for child in REPORTS.iterdir():
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
    else:
        REPORTS.mkdir(parents=True)


def mask_ip(value):
    return value.rsplit('.', 1)[0] + '.XXX'


def mask_email(value):
    local, domain = value.split('@', 1)
    return local[:2] + '***@' + domain


def mask_user(value):
    return value[0] + '***' + value[-1]


def install_fixture(servers, changes):
    SERVERS.write_text(
        'ServerID,Region,IPAddress,OwnerEmail\n'
        + ''.join(','.join(row) + '\n' for row in servers)
    )
    CHANGES.write_text(
        'ServerID,Timestamp,UserID,ConfigKey,NewValue\n'
        + ''.join(','.join(row) + '\n' for row in changes)
    )


def expected_reports(servers, changes):
    metadata = {row[0]: row for row in servers}
    expected = {}
    for server_id, timestamp, user_id, key, value in changes:
        if server_id not in metadata:
            continue
        _, region, ip, email = metadata[server_id]
        text = (
            f'Server: {server_id}\n'
            f'IP: {mask_ip(ip)}\n'
            f'Admin: {mask_email(email)}\n'
            f'Changed {key} to {value} by {mask_user(user_id)} at {timestamp}\n'
            '---\n'
        )
        expected.setdefault(f'region_{region}.txt', '')
        expected[f'region_{region}.txt'] += text
    return expected


def assert_reports(expected):
    assert REPORTS.exists(), f"Reports directory missing: {REPORTS}"
    assert REPORTS.is_dir(), f"Reports path is not a directory: {REPORTS}"
    actual_names = {p.name for p in REPORTS.iterdir()}
    assert actual_names == set(expected), f"Unexpected report files: {actual_names}; expected {set(expected)}"
    for filename, wanted in expected.items():
        actual = (REPORTS / filename).read_text()
        assert actual.strip() == wanted.strip(), f"Content mismatch in {REPORTS / filename}"


def randomized_fixture():
    token = uuid.uuid4().hex[:10]
    region_a = f'QA-East-{token}'
    region_b = f'QA-West-{token}'
    server_a = f'NODEA{token}'
    server_b = f'NODEB{token}'
    server_unused = f'IDLE{token}'
    servers = [
        (server_a, region_a, '203.0.113.47', f'alpha{token}@example.test'),
        (server_b, region_b, '198.51.100.208', f'bravo{token}@internal.test'),
        (server_unused, f'Unused-{token}', '192.0.2.19', f'idle{token}@example.test'),
    ]
    changes = [
        (server_b, f'2042-01-01T01:02:{token[:2]}Z', f'Q{token}9', f'Feature{token}', f'On{token}'),
        (server_a, f'2042-01-02T03:04:{token[2:4]}Z', f'R{token}8', f'Limit{token}', f'73{token}'),
        (f'MISSING{token}', '2042-01-03T00:00:00Z', f'X{token}Y', 'Ignored', 'ignored'),
        (server_b, f'2042-01-04T05:06:{token[4:6]}Z', f'S{token}7', f'Mode{token}', f'Safe{token}'),
    ]
    return servers, changes


def test_pipeline_script_exists_and_executable():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.exists(script_path), f"Pipeline script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Pipeline script is not executable: {script_path}"


def test_cpp_source_exists():
    cpp_path = '/home/user/process_configs.cpp'
    assert os.path.exists(cpp_path), f"C++ source file missing: {cpp_path}"


def test_pipeline_runs_on_original_fixture():
    SERVERS.write_text(ORIGINAL_SERVERS)
    CHANGES.write_text(ORIGINAL_CHANGES)
    run_checked([str(SCRIPT)])


def test_reports_directory_exists():
    reports_dir = '/home/user/reports'
    assert os.path.exists(reports_dir), f"Reports directory missing: {reports_dir}"
    assert os.path.isdir(reports_dir), f"Reports path is not a directory: {reports_dir}"


def test_us_east_report_content():
    report_path = '/home/user/reports/region_US-East.txt'
    assert os.path.exists(report_path), f"Report file missing: {report_path}"
    expected_content = (
        "Server: S1\n"
        "IP: 10.0.0.XXX\n"
        "Admin: ad***@company.com\n"
        "Changed MaxConnections to 100 by U***5 at 2023-10-01T10:00:00Z\n"
        "---\n"
        "Server: S1\n"
        "IP: 10.0.0.XXX\n"
        "Admin: ad***@company.com\n"
        "Changed Port to 8080 by U***5 at 2023-10-02T09:00:00Z\n"
        "---\n"
    )
    with open(report_path, 'r') as f:
        content = f.read()
    assert content.strip() == expected_content.strip(), f"Content mismatch in {report_path}"


def test_eu_west_report_content():
    report_path = '/home/user/reports/region_EU-West.txt'
    assert os.path.exists(report_path), f"Report file missing: {report_path}"
    expected_content = (
        "Server: S2\n"
        "IP: 192.168.100.XXX\n"
        "Admin: sy***@company.com\n"
        "Changed Timeout to 30 by U***5 at 2023-10-01T11:00:00Z\n"
        "---\n"
        "Server: S2\n"
        "IP: 192.168.100.XXX\n"
        "Admin: sy***@company.com\n"
        "Changed SSL to true by U***5 at 2023-10-04T14:20:00Z\n"
        "---\n"
    )
    with open(report_path, 'r') as f:
        content = f.read()
    assert content.strip() == expected_content.strip(), f"Content mismatch in {report_path}"


def test_us_west_report_content():
    report_path = '/home/user/reports/region_US-West.txt'
    assert os.path.exists(report_path), f"Report file missing: {report_path}"
    expected_content = (
        "Server: S3\n"
        "IP: 172.16.5.XXX\n"
        "Admin: de***@internal.net\n"
        "Changed LogLevel to DEBUG by A***Z at 2023-10-03T08:15:00Z\n"
        "---\n"
    )
    with open(report_path, 'r') as f:
        content = f.read()
    assert content.strip() == expected_content.strip(), f"Content mismatch in {report_path}"


def test_pipeline_processes_unseen_inputs_and_clears_reports():
    servers, changes = randomized_fixture()
    install_fixture(servers, changes)
    REPORTS.mkdir(parents=True, exist_ok=True)
    stale = REPORTS / 'stale_report.txt'
    stale.write_text('must be removed')
    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()

    run_checked([str(SCRIPT)])

    assert not stale.exists(), 'Pipeline did not clear the reports directory'
    assert BINARY.is_file(), 'Pipeline did not create /home/user/process_configs'
    assert os.access(BINARY, os.X_OK), 'Compiled program is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'Pipeline output is not a compiled ELF program'
    assert_reports(expected_reports(servers, changes))


def test_cpp_program_compiles_and_processes_another_unseen_fixture():
    servers, changes = randomized_fixture()
    install_fixture(servers, changes)
    clear_reports()
    test_binary = Path('/tmp') / f'process_configs_{uuid.uuid4().hex}'
    try:
        run_checked(['g++', '-std=c++17', str(SOURCE), '-o', str(test_binary)], timeout=60)
        assert test_binary.read_bytes()[:4] == b'\x7fELF'
        run_checked([str(test_binary)])
        assert_reports(expected_reports(servers, changes))
    finally:
        if test_binary.exists():
            test_binary.unlink()


def test_orchestrator_compiles_and_executes_its_cpp_source():
    original_source = SOURCE.read_bytes()
    original_mode = stat.S_IMODE(SOURCE.stat().st_mode)
    marker = Path('/tmp') / f'pipeline_marker_{uuid.uuid4().hex}'
    probe = (
        '#include <fstream>\n'
        'int main() { std::ofstream out("' + str(marker) + '"); out << "executed"; return 0; }\n'
    )
    REPORTS.mkdir(parents=True, exist_ok=True)
    stale = REPORTS / f'stale_{uuid.uuid4().hex}.txt'
    stale.write_text('stale')
    try:
        SOURCE.write_text(probe)
        if BINARY.exists() or BINARY.is_symlink():
            BINARY.unlink()
        run_checked([str(SCRIPT)])
        assert marker.read_text() == 'executed', 'Orchestrator did not execute the program compiled from process_configs.cpp'
        assert not stale.exists(), 'Orchestrator did not clear the reports directory'
        assert BINARY.is_file() and BINARY.read_bytes()[:4] == b'\x7fELF'
    finally:
        SOURCE.write_bytes(original_source)
        os.chmod(SOURCE, original_mode)
        if marker.exists():
            marker.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
