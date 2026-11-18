#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

HOME = Path('/home/user')
SCRIPT = HOME / 'verify_migration.py'
REPORT = HOME / 'test_report.txt'
LOG = HOME / 'migration.log'
V1 = HOME / 'artifacts/v1'
V2 = HOME / 'artifacts/v2'


def run_script():
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{SCRIPT} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert REPORT.is_file(), f'The script did not create {REPORT}.'


def report_lines():
    content = REPORT.read_text()
    return [line.strip() for line in content.splitlines() if line.strip()]


def reset_artifacts():
    shutil.rmtree(HOME / 'artifacts', ignore_errors=True)
    V1.mkdir(parents=True)
    V2.mkdir(parents=True)


def write_artifact(artifact_id, *, version=2, output_id=None, valid_checksum=True):
    raw = ('{\n  "data": "payload-' + artifact_id + '",\n  "id": "' + artifact_id + '"\n}\n').encode()
    (V1 / f'{artifact_id}.json').write_bytes(raw)
    checksum = hashlib.md5(raw).hexdigest() if valid_checksum else '0' * 32
    v2 = {
        'id': artifact_id if output_id is None else output_id,
        'version': version,
        'checksum': checksum,
    }
    (V2 / f'{artifact_id}.json').write_text(json.dumps(v2))


def test_verify_migration_script_exists():
    script_path = '/home/user/verify_migration.py'
    assert os.path.isfile(script_path), f'The script {script_path} was not created.'


def test_test_report_exists_and_correct():
    run_script()
    report_path = '/home/user/test_report.txt'
    assert os.path.isfile(report_path), f'The report file {report_path} was not created.'

    with open(report_path, 'r') as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = ['art-2', 'art-4']

    assert lines == expected_lines, (
        f'The contents of {report_path} do not match the expected output.\n'
        f'Expected:\n{chr(10).join(expected_lines)}\n\n'
        f'Got:\n{chr(10).join(lines)}'
    )


def test_script_parses_log_and_validates_live_artifacts():
    backup = Path(tempfile.mkdtemp(prefix='migration-verifier-backup-'))
    shutil.copy2(LOG, backup / 'migration.log')
    shutil.copytree(HOME / 'artifacts', backup / 'artifacts')
    if REPORT.exists():
        shutil.copy2(REPORT, backup / 'test_report.txt')

    token = uuid.uuid4().hex[:10]
    good = f'good-{token}'
    bad_checksum = f'checksum-{token}'
    bad_id = f'id-{token}'
    bad_version = f'version-{token}'
    failed = f'failed-{token}'
    orphan = f'orphan-{token}'
    dangling = f'dangling-{token}'

    try:
        reset_artifacts()
        write_artifact(good)
        write_artifact(bad_checksum, valid_checksum=False)
        write_artifact(bad_id, output_id=f'other-{token}')
        write_artifact(bad_version, version=1)
        write_artifact(failed, valid_checksum=False)
        write_artifact(orphan, valid_checksum=False)
        write_artifact(dangling, valid_checksum=False)

        LOG.write_text('\n'.join([
            '[INFO] verifier-generated migration run',
            f'[INFO] SUCCESS {orphan}',
            f'[INFO] START migrate {good}',
            '[DEBUG] arbitrary noise between states',
            f'[INFO] SUCCESS {good}',
            f'[INFO] START migrate {bad_checksum}',
            f'[INFO] SUCCESS {bad_checksum}',
            f'[INFO] START migrate {failed}',
            f'[ERROR] FAIL {failed}',
            f'[INFO] START migrate {bad_id}',
            f'[INFO] SUCCESS {bad_id}',
            f'[INFO] START migrate {bad_version}',
            f'[INFO] SUCCESS {bad_version}',
            f'[INFO] START migrate {dangling}',
            '',
        ]))

        run_script()
        expected = sorted([bad_checksum, bad_id, bad_version])
        assert report_lines() == expected, (
            'The report did not reflect state-machine parsing and validation of '
            f'the verifier-generated artifacts. Expected {expected}, got {report_lines()}.'
        )

        all_pass_a = f'pass-a-{uuid.uuid4().hex[:10]}'
        all_pass_b = f'pass-b-{uuid.uuid4().hex[:10]}'
        reset_artifacts()
        write_artifact(all_pass_a)
        write_artifact(all_pass_b)
        LOG.write_text('\n'.join([
            f'[INFO] START migrate {all_pass_b}',
            '[TRACE] noise',
            f'[INFO] SUCCESS {all_pass_b}',
            f'[INFO] START migrate {all_pass_a}',
            f'[INFO] SUCCESS {all_pass_a}',
            '',
        ]))

        run_script()
        assert REPORT.read_text().strip() == 'ALL PASS', (
            'A run in which every successfully migrated artifact was valid must '
            'produce ALL PASS.'
        )
    finally:
        shutil.rmtree(HOME / 'artifacts', ignore_errors=True)
        shutil.copytree(backup / 'artifacts', HOME / 'artifacts')
        shutil.copy2(backup / 'migration.log', LOG)
        if (backup / 'test_report.txt').exists():
            shutil.copy2(backup / 'test_report.txt', REPORT)
        elif REPORT.exists():
            REPORT.unlink()
        shutil.rmtree(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
