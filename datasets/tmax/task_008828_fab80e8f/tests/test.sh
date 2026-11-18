#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import json
import os
import pathlib
import secrets
import shutil
import subprocess

REPORT = pathlib.Path('/home/user/backup_report.csv')
CONFIG = pathlib.Path('/home/user/projects/config.json')

# Preserve the original verifier's exact report checks, corrected to reflect the
# literal backslash-n sequences actually created by setup.sh.
assert REPORT.is_file(), '/home/user/backup_report.csv does not exist. The script failed to generate the report.'
expected_rows = [
    ['project_name', 'file_name', 'file_type', 'header_info'],
    ['alpha', 'app.log', 'text', '[LOG] 2023-10-01 System Initialized\\nInitialization complete.\\nReady.'],
    ['alpha', 'data.dat', 'binary', 'DEADBEEF'],
    ['beta', 'cache.dat', 'binary', 'CAFEBABE'],
    ['beta', 'error.log', 'text', '[LOG] 2023-10-02 Warning Encountered\\nModule X failed to load.\\nRetry attempt 1.']
]
with REPORT.open('r', newline='') as f:
    actual_rows = list(csv.reader(f))
assert len(actual_rows) > 0, 'The CSV file is empty.'
assert actual_rows[0] == expected_rows[0], f'CSV header mismatch. Expected {expected_rows[0]}, got {actual_rows[0]}'
assert len(actual_rows) == len(expected_rows), f'CSV row count mismatch. Expected {len(expected_rows)} rows, got {len(actual_rows)}.'
for i in range(1, len(expected_rows)):
    assert actual_rows[i] == expected_rows[i], f'CSV data mismatch at row {i + 1}. Expected {expected_rows[i]}, got {actual_rows[i]}'

# Locate a persistent Python artifact written by the agent.
candidates = []
for root, dirs, files in os.walk('/home/user', followlinks=False):
    dirs[:] = [d for d in dirs if not pathlib.Path(root, d).is_symlink()]
    for name in files:
        p = pathlib.Path(root, name)
        if p.suffix == '.py' and p.is_file() and not p.is_symlink():
            candidates.append(p)
assert candidates, 'No Python script was found under /home/user.'

original_config = CONFIG.read_bytes()
original_report = REPORT.read_bytes()
token = secrets.token_hex(6)
test_root = pathlib.Path('/home/user') / ('.verifier_catalog_' + token)
project_a = 'aardvark_' + token
project_z = 'zeta_' + token
adir = test_root / 'a_logs'
zdir = test_root / 'z_logs'

log_a_name = 'middle_' + token + '.log'
dat_a_name = 'omega_' + token + '.dat'
log_z_name = 'alpha_' + token + '.log'
dat_z_name = 'beta_' + token + '.dat'
header_a = 'Header, A ' + token
header_z = 'Header Z ' + token
magic_a = os.urandom(4)
magic_z = os.urandom(4)

expected_dynamic = [
    ['project_name', 'file_name', 'file_type', 'header_info'],
    [project_a, log_a_name, 'text', header_a],
    [project_a, dat_a_name, 'binary', magic_a.hex().upper()],
    [project_z, log_z_name, 'text', header_z],
    [project_z, dat_z_name, 'binary', magic_z.hex().upper()],
]

def prepare_fixture():
    if test_root.exists():
        shutil.rmtree(test_root)
    (adir / 'nested').mkdir(parents=True)
    (zdir / 'nested' / 'deeper').mkdir(parents=True)
    (adir / 'nested' / log_a_name).write_bytes((header_a + '\nsecond line\n').encode())
    (adir / dat_a_name).write_bytes(magic_a + b'EXTRA-DATA')
    (zdir / log_z_name).write_bytes((header_z + '\nignored line\n').encode())
    (zdir / 'nested' / 'deeper' / dat_z_name).write_bytes(magic_z + b'REMAINDER')

    # Supported-extension symlinks and recursive/cross-directory links must all
    # be ignored rather than reported or followed.
    os.symlink(adir / 'nested' / log_a_name, adir / ('linked_' + token + '.log'))
    os.symlink(zdir / 'nested' / 'deeper' / dat_z_name, zdir / ('linked_' + token + '.dat'))
    os.symlink(adir, adir / 'nested' / 'recursive_loop')
    os.symlink(adir, zdir / 'cross_link')

    CONFIG.write_text(json.dumps({'projects': [
        {'name': project_z, 'log_dir': str(zdir)},
        {'name': project_a, 'log_dir': str(adir)},
    ]}))
    try:
        REPORT.unlink()
    except FileNotFoundError:
        pass

passed_by = None
errors = []
try:
    for candidate in sorted(candidates):
        prepare_fixture()
        try:
            result = subprocess.run(
                ['python3', str(candidate)],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                check=False,
            )
            if result.returncode != 0:
                errors.append(f'{candidate}: exited {result.returncode}')
                continue
            if not REPORT.is_file():
                errors.append(f'{candidate}: did not create the report')
                continue
            with REPORT.open('r', newline='') as f:
                rows = list(csv.reader(f))
            if rows == expected_dynamic:
                passed_by = candidate
                break
            errors.append(f'{candidate}: generated incorrect dynamic report')
        except subprocess.TimeoutExpired:
            errors.append(f'{candidate}: timed out, possibly following a symlink loop')
        except Exception as exc:
            errors.append(f'{candidate}: {exc}')
    assert passed_by is not None, 'No submitted Python script correctly handled a dynamic configuration, nested files, metadata, sorting, and symlink loops. ' + '; '.join(errors)
finally:
    CONFIG.write_bytes(original_config)
    REPORT.write_bytes(original_report)
    if test_root.exists():
        shutil.rmtree(test_root)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
