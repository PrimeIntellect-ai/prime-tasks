#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

SOURCE = '/home/user/audit.c'
AUDIT_DIR = '/home/user/ssh_audit'
REPORT = '/home/user/audit_results.txt'


def run_program(binary):
    if os.path.lexists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', binary],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Audit program exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


@pytest.fixture(scope='session', autouse=True)
def compiled_program():
    assert os.path.lexists(SOURCE), 'The file /home/user/audit.c does not exist.'
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), '/home/user/audit.c must be a regular file.'

    build_dir = tempfile.mkdtemp(prefix='audit_verifier_')
    os.chmod(build_dir, 0o755)
    binary = os.path.join(build_dir, 'audit')
    result = subprocess.run(
        ['gcc', SOURCE, '-o', binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'/home/user/audit.c did not compile successfully.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    os.chmod(binary, 0o755)
    run_program(binary)
    yield binary
    shutil.rmtree(build_dir, ignore_errors=True)


def read_report():
    with open(REPORT, 'r') as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def expected_report():
    lines = []
    for name in os.listdir(AUDIT_DIR):
        path = os.path.join(AUDIT_DIR, name)
        if not os.path.isfile(path):
            continue
        mode = stat.S_IMODE(os.stat(path).st_mode)
        bad = False
        if name.endswith('.pub'):
            bad = mode != 0o644
        elif name == 'config':
            bad = mode not in (0o600, 0o644)
        elif name == 'authorized_keys':
            bad = mode != 0o600
        elif 'id_rsa' in name or 'id_ed25519' in name:
            bad = mode != 0o600
        if bad:
            lines.append(f'{name}:{mode:04o}')
    return sorted(lines, key=lambda line: line.split(':', 1)[0])


def test_audit_results_exists():
    """Verify that the audit_results.txt file was created by the compiled program."""
    assert os.path.isfile(REPORT), 'The file /home/user/audit_results.txt does not exist.'


def test_audit_results_content():
    """Verify that the initial report contains the correct filename-sorted output."""
    expected_lines = [
        'backup_id_rsa:0777',
        'config:0755',
        'id_rsa:0644',
        'id_rsa.pub:0666',
    ]
    actual_lines = read_report()
    assert actual_lines == expected_lines, (
        'The contents of /home/user/audit_results.txt do not match the expected output.\n'
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_compiled_program_handles_changed_inputs(compiled_program):
    original_modes = {
        name: stat.S_IMODE(os.stat(os.path.join(AUDIT_DIR, name)).st_mode)
        for name in os.listdir(AUDIT_DIR)
        if os.path.isfile(os.path.join(AUDIT_DIR, name))
    }
    token = secrets.token_hex(8)
    added = [
        f'{token}.pub',
        f'{token}_id_rsa_key',
        f'{token}_id_ed25519_key',
        f'{token}_ignored.txt',
    ]

    try:
        for name in added:
            with open(os.path.join(AUDIT_DIR, name), 'w'):
                pass

        scenarios = [
            {
                'config': 0o644,
                'authorized_keys': 0o666,
                'id_rsa': 0o600,
                'id_rsa.pub': 0o600,
                added[0]: 0o600,
                added[1]: 0o640,
                added[2]: 0o600,
                added[3]: 0o000,
            },
            {
                'config': 0o700,
                'authorized_keys': 0o600,
                'id_ed25519': 0o666,
                'id_ed25519.pub': 0o644,
                added[0]: 0o644,
                added[1]: 0o600,
                added[2]: 0o777,
                added[3]: 0o777,
            },
        ]

        for modes in scenarios:
            for name, mode in modes.items():
                os.chmod(os.path.join(AUDIT_DIR, name), mode)
            run_program(compiled_program)
            assert os.path.isfile(REPORT), 'The program did not recreate audit_results.txt.'
            assert read_report() == expected_report()
    finally:
        for name, mode in original_modes.items():
            path = os.path.join(AUDIT_DIR, name)
            if os.path.exists(path):
                os.chmod(path, mode)
        for name in added:
            path = os.path.join(AUDIT_DIR, name)
            if os.path.lexists(path):
                os.unlink(path)
        run_program(compiled_program)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
