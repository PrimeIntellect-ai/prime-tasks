#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
from pathlib import Path

import pytest

HOME = Path('/home/user')
STAGING = HOME / 'restore_staging'
REPORT = HOME / 'restore_report.json'
INPUTS = [HOME / 'backup.tar.gz', HOME / 'backup_manifest.json', HOME / 'quotas.json']
EXPECTED_CANONICAL = {
    'file_a.dat': 'ok',
    'file_b.dat': 'quota_exceeded',
    'file_c.dat': 'quota_exceeded',
    'file_d.dat': 'size_mismatch',
}


def assert_original_state():
    assert STAGING.is_dir(), f'Directory {STAGING} does not exist. Did you extract the tarball to the correct location?'
    for name in ['file_a.dat', 'file_b.dat', 'file_c.dat', 'file_d.dat']:
        path = STAGING / name
        assert path.is_file(), f'Extracted file {path} is missing. The tarball was not extracted correctly.'

    assert REPORT.is_file(), f'File {REPORT} does not exist. Did you generate the final report?'
    try:
        report_data = json.loads(REPORT.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'{REPORT} is not a valid JSON file.')
    assert report_data == EXPECTED_CANONICAL, \
        f'The contents of {REPORT} do not match the expected verification results. Got: {report_data}'


def assert_archive_was_extracted(archive_path):
    with tarfile.open(archive_path, 'r:gz') as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            extracted = STAGING / member.name
            assert extracted.is_file(), f'Archive member {member.name} was not extracted'
            expected = archive.extractfile(member).read()
            assert extracted.read_bytes() == expected, \
                f'Extracted content for {member.name} does not match the archive'


def clear_outputs():
    if STAGING.is_symlink() or (STAGING.exists() and not STAGING.is_dir()):
        STAGING.unlink()
    elif STAGING.exists():
        shutil.rmtree(STAGING)
    if REPORT.is_dir() and not REPORT.is_symlink():
        shutil.rmtree(REPORT)
    elif REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()


def scripts_in_home():
    result = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != 'restore_staging']
        for name in files:
            if not name.endswith('.py'):
                continue
            path = Path(root) / name
            try:
                if stat.S_ISREG(path.lstat().st_mode):
                    result.append(path)
            except FileNotFoundError:
                pass
    return sorted(result)


def run_script(script):
    clear_outputs()

    def become_user():
        os.setgid(1000)
        os.setuid(1000)

    env = os.environ.copy()
    env['HOME'] = str(HOME)
    return subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
        preexec_fn=become_user,
    )


def write_archive(entries):
    with tarfile.open(INPUTS[0], 'w:gz') as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def expected_report(manifest, quotas, actual_sizes):
    running = {str(uid): int(values['used']) for uid, values in quotas.items()}
    result = {}
    for item in manifest:
        path = item['path']
        size = int(item['size'])
        uid = str(item['uid'])
        if path not in actual_sizes or actual_sizes[path] != size:
            result[path] = 'size_mismatch'
        elif running[uid] + size > int(quotas[uid]['limit']):
            result[path] = 'quota_exceeded'
        else:
            result[path] = 'ok'
            running[uid] += size
    return result


def install_dynamic_fixture():
    token = secrets.token_hex(6)
    first_size = secrets.randbelow(20) + 11
    final_size = secrets.randbelow(8) + 3
    rejected_size = final_size + secrets.randbelow(12) + 5
    mismatch_expected = secrets.randbelow(15) + 10

    names = {
        'first': f'{token}/first.bin',
        'rejected': f'{token}/second.bin',
        'mismatch': f'{token}/nested/wrong.bin',
        'missing': f'{token}/missing.bin',
        'final': f'{token}/last.bin',
        'other': f'{token}/other.bin',
    }
    uid1 = 4101
    uid2 = 4102
    used1 = secrets.randbelow(10) + 2
    limit1 = used1 + first_size + final_size
    other_size = secrets.randbelow(12) + 4

    manifest = [
        {'path': names['first'], 'uid': uid1, 'size': first_size},
        {'path': names['rejected'], 'uid': uid1, 'size': rejected_size},
        {'path': names['mismatch'], 'uid': uid1, 'size': mismatch_expected},
        {'path': names['missing'], 'uid': uid2, 'size': 7},
        {'path': names['final'], 'uid': uid1, 'size': final_size},
        {'path': names['other'], 'uid': uid2, 'size': other_size},
    ]
    quotas = {
        str(uid1): {'used': used1, 'limit': limit1},
        str(uid2): {'used': 20, 'limit': 20 + other_size - 1},
    }
    entries = {
        names['first']: os.urandom(first_size),
        names['rejected']: os.urandom(rejected_size),
        names['mismatch']: os.urandom(mismatch_expected + 3),
        names['final']: os.urandom(final_size),
        names['other']: os.urandom(other_size),
    }
    write_archive(entries)
    INPUTS[1].write_text(json.dumps(manifest))
    INPUTS[2].write_text(json.dumps(quotas))
    actual_sizes = {name: len(data) for name, data in entries.items()}
    return expected_report(manifest, quotas, actual_sizes)


def test_00_original_final_state():
    # Preserve the original verifier's assertions.
    assert_original_state()
    assert_archive_was_extracted(INPUTS[0])


def test_10_python_automation_executes_and_handles_derived_inputs():
    original = {path: path.read_bytes() for path in INPUTS}
    candidates = scripts_in_home()
    assert candidates, 'No Python automation script was written under /home/user'

    failures = []
    winner = None
    try:
        for script in candidates:
            try:
                dynamic_expected = install_dynamic_fixture()
                dynamic_inputs = {path: path.read_bytes() for path in INPUTS}
                completed = run_script(script)
                if completed.returncode != 0:
                    failures.append(f'{script}: exited {completed.returncode}: {completed.stdout[-500:]}')
                    continue
                if any(path.read_bytes() != data for path, data in dynamic_inputs.items()):
                    failures.append(f'{script}: modified an input file')
                    continue
                if not REPORT.is_file():
                    failures.append(f'{script}: did not create restore_report.json')
                    continue
                try:
                    report = json.loads(REPORT.read_text())
                except Exception as exc:
                    failures.append(f'{script}: invalid report JSON: {exc}')
                    continue
                if report != dynamic_expected:
                    failures.append(f'{script}: dynamic report was {report}, expected {dynamic_expected}')
                    continue
                try:
                    assert_archive_was_extracted(INPUTS[0])
                except AssertionError as exc:
                    failures.append(f'{script}: {exc}')
                    continue
                winner = script
                break
            except (subprocess.TimeoutExpired, OSError, ValueError) as exc:
                failures.append(f'{script}: {exc}')

        assert winner is not None, 'No Python script correctly automated the restore verification. ' + ' | '.join(failures)

        for path, data in original.items():
            path.write_bytes(data)
        canonical_inputs = {path: path.read_bytes() for path in INPUTS}
        completed = run_script(winner)
        assert completed.returncode == 0, f'{winner} failed on the supplied inputs: {completed.stdout}'
        assert all(path.read_bytes() == data for path, data in canonical_inputs.items()), \
            'The automation script changed an input file'
        assert_original_state()
        assert_archive_was_extracted(INPUTS[0])
    finally:
        for path, data in original.items():
            path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
