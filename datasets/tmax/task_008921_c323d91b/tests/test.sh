#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import stat
import subprocess
import textwrap
import uuid
from pathlib import Path

import pytest


def test_run_export_uses_pexpect_and_executes_exporter():
    run_export = Path('/home/user/run_export.py')
    legacy = Path('/home/user/legacy_export.py')
    export_root = Path('/home/user/export_data')

    assert run_export.is_file(), f'Script {run_export} was not created.'

    source = run_export.read_text()
    tree = ast.parse(source, filename=str(run_export))
    assert any(
        (isinstance(node, ast.Import) and any(alias.name == 'pexpect' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'pexpect')
        for node in ast.walk(tree)
    ), 'run_export.py must import pexpect.'

    nonce = uuid.uuid4().hex
    completion_marker = Path(f'/tmp/export_completed_{nonce}')
    pexpect_marker = Path(f'/tmp/pexpect_used_{nonce}')
    hook_dir = Path(f'/tmp/pexpect_hook_{nonce}')
    hook_dir.mkdir()

    (hook_dir / 'sitecustomize.py').write_text(textwrap.dedent(f'''\
        import pexpect

        _marker = {str(pexpect_marker)!r}

        def _record():
            with open(_marker, 'a') as f:
                f.write('called\\n')

        for _name in ('spawn', 'spawnu', 'run', 'runu'):
            if hasattr(pexpect, _name):
                _original = getattr(pexpect, _name)
                def _make_wrapper(original):
                    def wrapper(*args, **kwargs):
                        _record()
                        return original(*args, **kwargs)
                    return wrapper
                setattr(pexpect, _name, _make_wrapper(_original))
    '''))

    original_legacy = legacy.read_bytes()
    original_mode = stat.S_IMODE(legacy.stat().st_mode)
    challenge = textwrap.dedent(f'''\
        #!/usr/bin/env python3
        import os
        import secrets
        import sys
        import time

        if not sys.stdin.isatty():
            print('A terminal is required.', flush=True)
            sys.exit(40)

        print('Legacy Storage Exporter v1.0', flush=True)
        pwd = input('Enter admin password: ')
        if pwd != 'cloud_admin_99':
            print('Auth failed!', flush=True)
            sys.exit(1)

        path = input('Enter export path: ')
        if path != '/home/user/export_data':
            print('Wrong export path!', flush=True)
            sys.exit(2)

        print(f'Exporting to {{path}}...', flush=True)
        time.sleep(0.75)
        token = secrets.token_hex(24)
        os.makedirs(path + '/app1', exist_ok=True)
        os.makedirs(path + '/db_data', exist_ok=True)
        with open(path + '/app1/config.txt', 'w') as f:
            f.write('app1 challenge ' + token)
        with open(path + '/db_data/schema.sql', 'w') as f:
            f.write('schema challenge ' + token)
        with open({str(completion_marker)!r}, 'w') as f:
            f.write(token)
        print('Export complete.', flush=True)
    ''')

    try:
        if export_root.exists() or export_root.is_symlink():
            if export_root.is_symlink() or export_root.is_file():
                export_root.unlink()
            else:
                shutil.rmtree(export_root)

        legacy.write_text(challenge)
        legacy.chmod(0o755)
        env = os.environ.copy()
        env['PYTHONPATH'] = str(hook_dir)
        result = subprocess.run(
            ['python3', str(run_export)],
            cwd='/home/user',
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f'run_export.py failed with exit code {result.returncode}. '
            f'stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        assert pexpect_marker.is_file() and pexpect_marker.read_text().strip(), (
            'run_export.py did not invoke pexpect to run the exporter.'
        )
        assert completion_marker.is_file(), (
            'The legacy exporter did not run to completion; run_export.py must wait for it.'
        )
        token = completion_marker.read_text()
        assert (export_root / 'app1/config.txt').read_text() == 'app1 challenge ' + token
        assert (export_root / 'db_data/schema.sql').read_text() == 'schema challenge ' + token
    finally:
        legacy.write_bytes(original_legacy)
        legacy.chmod(original_mode)
        shutil.rmtree(hook_dir, ignore_errors=True)
        completion_marker.unlink(missing_ok=True)
        pexpect_marker.unlink(missing_ok=True)


def test_setup_mounts_parses_configuration_and_is_idempotent():
    setup_mounts = Path('/home/user/setup_mounts.py')
    fstab = Path('/home/user/migration_fstab')
    assert setup_mounts.is_file(), f'Script {setup_mounts} was not created.'
    ast.parse(setup_mounts.read_text(), filename=str(setup_mounts))

    nonce = uuid.uuid4().hex
    source_name = f'verifier_source_{nonce}'
    source = Path('/home/user/export_data') / source_name
    target = Path('/home/user/cloud_mounts/verification') / nonce / 'mount'
    source.mkdir(parents=True)
    (source / 'payload.txt').write_text(nonce)

    original_fstab = fstab.read_bytes()
    try:
        with fstab.open('a') as f:
            f.write(f'\n# dynamically added verifier mapping\n\n{source_name} {target}\n')
            f.write('malformed_line_without_a_target\n')

        for iteration in (1, 2):
            result = subprocess.run(
                ['python3', str(setup_mounts)],
                cwd='/home/user',
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode == 0, (
                f'setup_mounts.py failed on run {iteration}. '
                f'stdout={result.stdout!r}, stderr={result.stderr!r}'
            )
            assert target.is_symlink(), f'{target} was not created as a symbolic link.'
            assert os.readlink(target) == str(source), f'{target} points to the wrong source.'
            assert (target / 'payload.txt').read_text() == nonce
    finally:
        fstab.write_bytes(original_fstab)


def test_migration_status_log():
    log_path = '/home/user/migration_status.log'
    assert os.path.isfile(log_path), f'Log file {log_path} does not exist.'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == 'MIGRATION_COMPLETE', f"Log file {log_path} does not contain exactly 'MIGRATION_COMPLETE'."


def test_exported_data_exists():
    app1_config = '/home/user/export_data/app1/config.txt'
    db_schema = '/home/user/export_data/db_data/schema.sql'

    assert os.path.isfile(app1_config), f'Exported file {app1_config} does not exist.'
    assert os.path.isfile(db_schema), f'Exported file {db_schema} does not exist.'


def test_symlinks_created():
    app1_link = '/home/user/cloud_mounts/srv/app1'
    db_link = '/home/user/cloud_mounts/var/lib/db'

    assert os.path.islink(app1_link), f'{app1_link} is not a symbolic link.'
    assert os.readlink(app1_link) == '/home/user/export_data/app1', f'Symlink {app1_link} points to the wrong target.'

    assert os.path.islink(db_link), f'{db_link} is not a symbolic link.'
    assert os.readlink(db_link) == '/home/user/export_data/db_data', f'Symlink {db_link} points to the wrong target.'


def test_scripts_exist():
    run_export_script = '/home/user/run_export.py'
    setup_mounts_script = '/home/user/setup_mounts.py'

    assert os.path.isfile(run_export_script), f'Script {run_export_script} was not created.'
    assert os.path.isfile(setup_mounts_script), f'Script {setup_mounts_script} was not created.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
