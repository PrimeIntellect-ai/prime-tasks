#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pathlib
import secrets
import shutil
import subprocess
import tempfile

PROJECT = pathlib.Path('/home/user/token_recovery')
TOKEN_FILE = pathlib.Path('/home/user/recovered_admin_token.txt')
AUTH_LOG = pathlib.Path('/home/user/auth.log')
CMDLINES = pathlib.Path('/home/user/cmdlines.txt')
AUTH_DAEMON = pathlib.Path('/home/user/auth_daemon')


def run_tool():
    if TOKEN_FILE.exists():
        TOKEN_FILE.unlink()
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['CARGO_HOME'] = '/home/user/.cargo'
    subprocess.run(
        ['cargo', 'run', '--quiet', '--offline', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), env=env, check=True, timeout=90,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert TOKEN_FILE.is_file(), f'The output file {TOKEN_FILE} does not exist.'
    return TOKEN_FILE.read_bytes()


def install_case(salt, matching_token, decoy_admin_token):
    digest = hashlib.sha256((matching_token + salt).encode()).hexdigest()
    AUTH_LOG.write_text(
        '[2023-10-01T12:00:00Z] SUCCESS User alice login attempt with hash: ' + '1' * 64 + '\n'
        '[2023-10-01T12:05:00Z] SUCCESS User admin login attempt with hash: ' + digest + '\n'
        '[2023-10-01T12:10:00Z] FAILED User bob login attempt with hash: ' + '2' * 64 + '\n'
    )
    CMDLINES.write_text(
        '/usr/bin/auth_worker --mode validate --token first_decoy --user alice\n'
        f'/usr/bin/auth_worker --mode validate --token {decoy_admin_token} --user admin\n'
        f'/usr/bin/auth_worker --mode validate --token {matching_token} --user bob\n'
        '/usr/bin/auth_worker --mode validate --token last_decoy --user unknown\n'
    )
    with tempfile.TemporaryDirectory() as td:
        source = pathlib.Path(td) / 'auth.c'
        binary = pathlib.Path(td) / 'auth_daemon'
        source.write_text(
            '#include <stdio.h>\n'
            f'const char* hidden_salt = "{salt}";\n'
            'int main(void) { puts("Auth Daemon Running..."); return 0; }\n'
        )
        subprocess.run(['gcc', str(source), '-o', str(binary)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        shutil.copyfile(binary, AUTH_DAEMON)
        AUTH_DAEMON.chmod(0o755)


def test_rust_project_and_recovery_workflow():
    assert PROJECT.is_dir(), 'The required /home/user/token_recovery project does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml is missing.'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'src/main.rs is missing.'
    assert (PROJECT / 'src' / 'main.rs').read_text().strip(), 'src/main.rs is empty.'

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['CARGO_HOME'] = '/home/user/.cargo'
    subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
         '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT), env=env, check=True, timeout=30,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    backups = {p: p.read_bytes() for p in (AUTH_LOG, CMDLINES, AUTH_DAEMON)}
    daemon_mode = AUTH_DAEMON.stat().st_mode
    try:
        # Execute the submitted Rust tool against the original artifacts.
        content = run_tool().decode()
        expected_token = 'super_secret_token_99'
        assert content == expected_token, (
            f'The recovered token is incorrect. '
            f'Expected exactly {repr(expected_token)} (no newlines), but got {repr(content)}.'
        )

        # Exercise parsing, salt extraction, hashing, and comparison on answers
        # generated only at verification time. The matching token is deliberately
        # not the token whose command line says --user admin.
        for _ in range(2):
            suffix = secrets.token_hex(10)
            salt = 'SALT_' + secrets.token_hex(8)
            matching = 'match_' + suffix
            decoy = 'admin_decoy_' + secrets.token_hex(8)
            install_case(salt, matching, decoy)
            assert run_tool() == matching.encode(), (
                'The Rust tool did not derive the token from the supplied log, '
                'binary salt, and leaked-token candidates.'
            )
    finally:
        for path, data in backups.items():
            path.write_bytes(data)
        AUTH_DAEMON.chmod(daemon_mode)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
