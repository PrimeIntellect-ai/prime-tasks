#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_config_manager.py
import ast
import configparser
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

BASE = Path('/home/user/config_manager')
SCRIPT = BASE / 'manager.py'


def check_original_assertions():
    log_path = BASE / 'results.log'
    assert log_path.is_file(), f'Log file {log_path} does not exist'
    content = log_path.read_text().splitlines()
    expected_lines = [
        'Corrupted: serverC_corrupted.tar.gz',
        'Processed: serverA - ApprovedCommit: def5678',
        'Processed: serverB - ApprovedCommit: z111111',
    ]
    for expected in expected_lines:
        assert expected in content, f"Expected line '{expected}' not found in results.log"

    conf_path = BASE / 'extracted/serverA/app.conf'
    assert conf_path.is_file(), f'Extracted config {conf_path} does not exist'
    content = conf_path.read_text()
    legacy_count = content.count('192.168.1.100')
    new_count = content.count('10.200.50.5')
    assert legacy_count == 0, f'Expected 0 occurrences of 192.168.1.100 in serverA/app.conf, found {legacy_count}'
    assert new_count == 501, f'Expected 501 occurrences of 10.200.50.5 in serverA/app.conf, found {new_count}'

    conf_path = BASE / 'extracted/serverB/app.conf'
    assert conf_path.is_file(), f'Extracted config {conf_path} does not exist'
    content = conf_path.read_text()
    legacy_count = content.count('192.168.1.100')
    new_count = content.count('10.200.50.5')
    assert legacy_count == 0, f'Expected 0 occurrences of 192.168.1.100 in serverB/app.conf, found {legacy_count}'
    assert new_count == 201, f'Expected 201 occurrences of 10.200.50.5 in serverB/app.conf, found {new_count}'

    rules_path = BASE / 'rules.ini'
    assert rules_path.is_file(), f'{rules_path} does not exist'
    config = configparser.ConfigParser()
    config.read(rules_path)
    assert config.has_section('Network'), 'rules.ini missing [Network] section'
    assert config.get('Network', 'legacy_ip') == '192.168.1.100', 'legacy_ip modified in rules.ini'
    assert config.get('Network', 'new_ip') == '10.200.50.5', 'new_ip modified in rules.ini'


def resolve_name(node, aliases):
    if isinstance(node, ast.Name):
        return aliases.get(node.id, node.id)
    if isinstance(node, ast.Attribute):
        base = resolve_name(node.value, aliases)
        return f'{base}.{node.attr}' if base else node.attr
    return ''


def inspect_script():
    assert SCRIPT.exists(), f'{SCRIPT} does not exist'
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} must be a regular Python file'
    source = SCRIPT.read_text()
    assert source.strip(), f'{SCRIPT} is empty'
    tree = ast.parse(source, filename=str(SCRIPT))

    aliases = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                aliases[item.asname or item.name.split('.')[0]] = item.name if item.asname else item.name.split('.')[0]
        elif isinstance(node, ast.ImportFrom) and node.module:
            for item in node.names:
                aliases[item.asname or item.name] = f'{node.module}.{item.name}'

    calls = [resolve_name(node.func, aliases) for node in ast.walk(tree) if isinstance(node, ast.Call)]
    concurrency_constructors = {
        'concurrent.futures.ThreadPoolExecutor',
        'concurrent.futures.ProcessPoolExecutor',
        'multiprocessing.Pool',
        'multiprocessing.pool.Pool',
        'multiprocessing.Process',
    }
    assert any(name in concurrency_constructors for name in calls), 'manager.py does not construct a multiprocessing/concurrent.futures worker pool'
    concurrency_methods = {'submit', 'map', 'starmap', 'imap', 'imap_unordered', 'apply_async', 'map_async', 'start'}
    assert any(name.rsplit('.', 1)[-1] in concurrency_methods for name in calls), 'manager.py does not dispatch work concurrently'

    fcntl_calls = {'fcntl.flock', 'fcntl.lockf'}
    if not any(name in fcntl_calls for name in calls):
        lock_constructors = {
            'filelock.FileLock', 'filelock.SoftFileLock',
            'portalocker.Lock', 'fasteners.InterProcessLock',
        }
        lock_vars = set()
        direct_lock_with = False
        for node in ast.walk(tree):
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                value = node.value
                if isinstance(value, ast.Call) and resolve_name(value.func, aliases) in lock_constructors:
                    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                    for target in targets:
                        if isinstance(target, ast.Name):
                            lock_vars.add(target.id)
            if isinstance(node, ast.With):
                for item in node.items:
                    expr = item.context_expr
                    if isinstance(expr, ast.Call) and resolve_name(expr.func, aliases) in lock_constructors:
                        direct_lock_with = True
                    if isinstance(expr, ast.Name) and expr.id in lock_vars:
                        direct_lock_with = True
        lock_methods = {'acquire', 'lock'}
        acquired = any(name.rsplit('.', 1)[-1] in lock_methods for name in calls)
        constructed = any(name in lock_constructors for name in calls)
        assert constructed and (direct_lock_with or acquired), 'manager.py does not acquire a file lock when writing the shared log'


def create_dynamic_fixture():
    token = secrets.token_hex(4)
    legacy_ip = f'172.{secrets.randbelow(100) + 20}.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    new_ip = f'10.{secrets.randbelow(100) + 100}.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'

    backups = BASE / 'backups'
    extracted = BASE / 'extracted'
    shutil.rmtree(backups, ignore_errors=True)
    shutil.rmtree(extracted, ignore_errors=True)
    backups.mkdir(parents=True)
    extracted.mkdir(parents=True)
    (BASE / 'results.log').unlink(missing_ok=True)
    (BASE / 'rules.ini').write_text(f'[Network]\nlegacy_ip = {legacy_ip}\nnew_ip = {new_ip}\n')

    expected_configs = {}
    expected_lines = []
    for index in range(4):
        name = f'node_{token}_{index}'
        first = f'old{secrets.token_hex(5)}'
        latest = f'good{secrets.token_hex(5)}'
        rejected = f'bad{secrets.token_hex(5)}'
        changelog = (
            '[Deployment: 2025-01-01]\n'
            f'CommitID: {first}\nStatus: APPROVED\nChanges:\n  - initial\n\n'
            '[Deployment: 2025-02-01]\n'
            f'CommitID: {latest}\nStatus: APPROVED\nChanges:\n  - approved update\n  - second line\n\n'
            '[Deployment: 2025-03-01]\n'
            f'CommitID: {rejected}\nStatus: REJECTED\nChanges:\n  - rejected later update\n'
        )
        original_conf = (
            f'primary={legacy_ip}:{8000 + index}\n'
            f'unchanged=203.0.113.{index + 1}\n'
            + ''.join(f'peer_{n}={legacy_ip}/24\n' for n in range(37 + index))
            + f'pair={legacy_ip},{legacy_ip}\n'
        )
        expected_configs[name] = original_conf.replace(legacy_ip, new_ip)

        staging = Path('/tmp') / f'fixture_{name}'
        shutil.rmtree(staging, ignore_errors=True)
        folder = staging / name
        folder.mkdir(parents=True)
        (folder / 'changelog.txt').write_text(changelog)
        (folder / 'app.conf').write_text(original_conf)
        with tarfile.open(backups / f'{name}.tar.gz', 'w:gz') as archive:
            archive.add(folder, arcname=name)
        shutil.rmtree(staging)
        expected_lines.append(f'Processed: {name} - ApprovedCommit: {latest}')

    corrupt_name = f'broken_{token}.tar.gz'
    (backups / corrupt_name).write_bytes(os.urandom(731))
    expected_lines.append(f'Corrupted: {corrupt_name}')
    return legacy_ip, new_ip, expected_configs, expected_lines, corrupt_name


def run_dynamic_test():
    legacy_ip, new_ip, expected_configs, expected_lines, corrupt_name = create_dynamic_fixture()
    completed = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(BASE),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, f'manager.py failed:\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}'

    log_path = BASE / 'results.log'
    assert log_path.is_file(), 'manager.py did not create results.log'
    actual_lines = [line for line in log_path.read_text().splitlines() if line]
    assert sorted(actual_lines) == sorted(expected_lines), f'Unexpected results.log contents: {actual_lines!r}'

    for name, expected in expected_configs.items():
        conf = BASE / 'extracted' / name / 'app.conf'
        assert conf.is_file(), f'Missing extracted configuration {conf}'
        actual = conf.read_text()
        assert actual == expected, f'Incorrect macro replacement in {conf}'
        assert legacy_ip not in actual, f'Legacy IP remains in {conf}'
        assert new_ip in actual, f'New IP is absent from {conf}'
        assert (BASE / 'extracted' / name / 'changelog.txt').is_file(), f'Missing extracted changelog for {name}'

    corrupt_folder = corrupt_name[:-7]
    assert not (BASE / 'extracted' / corrupt_folder).exists(), 'Corrupted archive was extracted'

    config = configparser.ConfigParser()
    config.read(BASE / 'rules.ini')
    assert config.get('Network', 'legacy_ip') == legacy_ip, 'manager.py modified legacy_ip in rules.ini'
    assert config.get('Network', 'new_ip') == new_ip, 'manager.py modified new_ip in rules.ini'


check_original_assertions()
inspect_script()
run_dynamic_test()
PY_EOF

if python3 /tmp/test_config_manager.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
