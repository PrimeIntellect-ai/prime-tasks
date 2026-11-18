#!/bin/bash
set +e
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import secrets
import shutil
import stat
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path

HOME = Path('/home/user')
ARCHIVE = HOME / 'backups' / 'infra_state.tar.gz'
EXTRACTED = HOME / 'extracted'
REPORT = HOME / 'report.json'
SCRIPT = HOME / 'extract_and_clean.sh'
PROJECT = HOME / 'state_parser'


def check_original_submission():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    st = SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {SCRIPT} is not executable.'

    alpha_conf = EXTRACTED / 'app_alpha' / 'servers.conf'
    beta_conf = EXTRACTED / 'app_beta' / 'servers.conf'
    assert alpha_conf.is_file(), f'Cleaned file {alpha_conf} does not exist.'
    assert beta_conf.is_file(), f'Cleaned file {beta_conf} does not exist.'

    alpha_lines = [line.strip() for line in alpha_conf.read_text().splitlines() if line.strip()]
    expected_alpha = ['192.168.1.10', '192.168.1.11', '10.0.0.5']
    assert alpha_lines == expected_alpha, f'Expected {alpha_conf} to have {expected_alpha}, got {alpha_lines}.'

    beta_lines = [line.strip() for line in beta_conf.read_text().splitlines() if line.strip()]
    expected_beta = ['172.16.0.4', '172.16.0.5']
    assert beta_lines == expected_beta, f'Expected {beta_conf} to have {expected_beta}, got {beta_lines}.'

    assert REPORT.is_file(), f'Report file {REPORT} does not exist.'
    try:
        report_data = json.loads(REPORT.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {REPORT} is not valid JSON.') from exc

    expected_data = {
        'admin_commits': 3,
        'apps': {
            'app_alpha': {
                'servers': ['192.168.1.10', '192.168.1.11', '10.0.0.5'],
                'config_keys': {'db_port': 5432, 'max_conn': 100},
            },
            'app_beta': {
                'servers': ['172.16.0.4', '172.16.0.5'],
                'config_keys': {'cache_size': 2048},
            },
        },
    }
    assert report_data == expected_data, f'Report JSON does not match expected output.\nExpected: {expected_data}\nGot: {report_data}'

    assert PROJECT.is_dir(), f'Rust project {PROJECT} does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'state_parser/Cargo.toml does not exist.'
    assert any(PROJECT.rglob('*.rs')), 'The state_parser project contains no Rust source files.'


def encode_state(records):
    out = bytearray(b'CFG\x01')
    out.extend(struct.pack('<I', len(records)))
    for key, version in records:
        key_bytes = key.encode('utf-8')
        assert len(key_bytes) <= 255
        out.append(len(key_bytes))
        out.extend(key_bytes)
        out.extend(struct.pack('<I', version))
    return bytes(out)


def make_log(records):
    chunks = []
    for commit_hash, author in records:
        chunks.append(f'Commit: {commit_hash}\nAuthor: {author}\nDate: 2026-09-12\n')
    return '---\n'.join(chunks) + '---\n'


def dynamic_test(tmp):
    token = secrets.token_hex(4)
    app_one = f'app_{token}_north'
    app_two = f'app_{token}_south'

    specs = {
        app_one: {
            'servers': [f'10.{secrets.randbelow(200)+1}.4.17', f'192.168.{secrets.randbelow(200)+1}.29'],
            'records': [(f'port_{token}', secrets.randbelow(50000)+1000), (f'workers_{token}', secrets.randbelow(1000)+1)],
            'log_records': [(secrets.token_hex(7), 'admin'), (secrets.token_hex(7), 'admin2'), (secrets.token_hex(7), 'operator')],
        },
        app_two: {
            'servers': [f'172.16.{secrets.randbelow(200)+1}.8', f'10.20.{secrets.randbelow(200)+1}.9', f'10.30.{secrets.randbelow(200)+1}.10'],
            'records': [(f'cache_{token}', secrets.randbelow(100000)+1)],
            'log_records': [(secrets.token_hex(7), 'admin'), (secrets.token_hex(7), 'user1'), (secrets.token_hex(7), 'admin')],
        },
    }

    outer = tmp / 'dynamic_infra_state.tar.gz'
    expected_files = {}
    inner_archives = []

    for index, (name, spec) in enumerate(specs.items()):
        source = tmp / f'source_{index}' / name
        source.mkdir(parents=True)
        servers = spec['servers']
        dirty = (
            f'   {servers[0]} ; primary node\n'
            f'; {secrets.token_hex(3)} disabled\n'
            f'\n  {servers[1]}   \n'
        )
        if len(servers) == 3:
            dirty += f'\t{servers[2]}; edge node\n'
        state_bytes = encode_state(spec['records'])
        log_text = make_log(spec['log_records'])
        (source / 'servers.conf').write_text(dirty)
        (source / 'state.bin').write_bytes(state_bytes)
        (source / 'changes.log').write_text(log_text)
        expected_files[name] = (state_bytes, log_text)

        inner = tmp / f'{name}.tar.bz2'
        with tarfile.open(inner, 'w:bz2') as archive:
            archive.add(source, arcname=name)
        inner_archives.append(inner)

    with tarfile.open(outer, 'w:gz') as archive:
        for inner in inner_archives:
            archive.add(inner, arcname=inner.name)

    shutil.copyfile(outer, ARCHIVE)
    subprocess.run([str(SCRIPT)], cwd=HOME, check=True, timeout=120)

    for name, spec in specs.items():
        app_dir = EXTRACTED / name
        conf = app_dir / 'servers.conf'
        state_file = app_dir / 'state.bin'
        log_file = app_dir / 'changes.log'
        assert conf.is_file(), f'{SCRIPT} did not extract {conf}'
        assert state_file.is_file(), f'{SCRIPT} did not extract {state_file}'
        assert log_file.is_file(), f'{SCRIPT} did not extract {log_file}'
        lines = conf.read_text().splitlines()
        assert lines == spec['servers'], f'{conf} was not cleaned correctly: {lines}'
        assert all(line == line.strip() and line and ';' not in line for line in lines)
        assert state_file.read_bytes() == expected_files[name][0], f'{state_file} was not correctly extracted.'
        assert log_file.read_text() == expected_files[name][1], f'{log_file} was not correctly extracted.'

    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()

    subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=PROJECT,
        check=True,
        timeout=180,
    )
    assert REPORT.is_file(), 'Running the Rust project did not create /home/user/report.json.'
    try:
        actual = json.loads(REPORT.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError('The dynamically generated report is not valid JSON.') from exc

    expected = {
        'admin_commits': sum(
            1 for spec in specs.values() for _, author in spec['log_records'] if author == 'admin'
        ),
        'apps': {
            name: {
                'servers': spec['servers'],
                'config_keys': {key: version for key, version in spec['records']},
            }
            for name, spec in specs.items()
        },
    }
    assert actual == expected, f'Rust parser failed dynamic input.\nExpected: {expected}\nGot: {actual}'


check_original_submission()
assert ARCHIVE.is_file(), f'Input archive {ARCHIVE} is missing.'

with tempfile.TemporaryDirectory(prefix='state_verifier_') as temp_name:
    temp = Path(temp_name)
    archive_backup = temp / 'original_infra_state.tar.gz'
    shutil.copy2(ARCHIVE, archive_backup)
    extracted_backup = temp / 'original_extracted'
    report_backup = temp / 'original_report.json'

    if EXTRACTED.exists() or EXTRACTED.is_symlink():
        shutil.move(str(EXTRACTED), str(extracted_backup))
    if REPORT.exists() or REPORT.is_symlink():
        shutil.move(str(REPORT), str(report_backup))

    try:
        dynamic_test(temp)
    finally:
        if EXTRACTED.exists() or EXTRACTED.is_symlink():
            if EXTRACTED.is_dir() and not EXTRACTED.is_symlink():
                shutil.rmtree(EXTRACTED)
            else:
                EXTRACTED.unlink()
        if REPORT.exists() or REPORT.is_symlink():
            REPORT.unlink()
        shutil.copy2(archive_backup, ARCHIVE)
        if extracted_backup.exists() or extracted_backup.is_symlink():
            shutil.move(str(extracted_backup), str(EXTRACTED))
        if report_backup.exists() or report_backup.is_symlink():
            shutil.move(str(report_backup), str(REPORT))
PY
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
