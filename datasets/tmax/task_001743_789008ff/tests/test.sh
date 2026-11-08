#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import io
import tarfile
import hashlib
import random
import secrets
import string
import subprocess
import tempfile
import uuid

SCRIPT_PATH = '/home/user/filter.sh'
SALT = 'zX9_config'
ACTIONS = ['INIT', 'UPDATE', 'REVERT']


def run_filter(path):
    return subprocess.run(
        ['bash', SCRIPT_PATH, path],
        capture_output=True,
        timeout=15,
    )


def checksum(action, key):
    return hashlib.md5((action + key + SALT).encode()).hexdigest()


def random_token(prefix):
    alphabet = string.ascii_letters + string.digits
    return prefix + ''.join(secrets.choice(alphabet) for _ in range(14))


def wal_line(action, key, value, supplied_checksum=None):
    digest = checksum(action, key) if supplied_checksum is None else supplied_checksum
    return f'[2026-08-19 12:34:56] {action} | {key} | {value} | {digest}\n'


def make_inner_archive(wals):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w:gz') as archive:
        for name, contents in wals:
            data = contents.encode()
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def create_generated_archive(path, defect=None):
    # Put the single defect at an unpredictable location so every WAL must be checked.
    positions = [(outer, wal, line) for outer in range(3) for wal in range(2) for line in range(2)]
    bad_position = secrets.choice(positions) if defect else None

    inner_archives = []
    for outer in range(3):
        wals = []
        for wal_index in range(2):
            lines = []
            for line_index in range(2):
                action = secrets.choice(ACTIONS)
                key = random_token('k')
                value = random_token('v')
                position = (outer, wal_index, line_index)

                if position == bad_position and defect == 'action':
                    action = random_token('FORBIDDEN_')
                    lines.append(wal_line(action, key, value))
                elif position == bad_position and defect == 'checksum':
                    correct = checksum(action, key)
                    wrong = secrets.token_hex(16)
                    while wrong == correct:
                        wrong = secrets.token_hex(16)
                    lines.append(wal_line(action, key, value, wrong))
                else:
                    lines.append(wal_line(action, key, value))

            wals.append((f'data/{uuid.uuid4().hex}.wal', ''.join(lines)))
        inner_archives.append((f'bundle_{uuid.uuid4().hex}.tar.gz', make_inner_archive(wals)))

    with tarfile.open(path, mode='w') as archive:
        for name, data in inner_archives:
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def test_filter_script_validation():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f'Script missing at {script_path}'

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_tars = glob.glob(os.path.join(clean_dir, '*.tar'))
    evil_tars = glob.glob(os.path.join(evil_dir, '*.tar'))

    assert len(clean_tars) > 0, f'No clean tar files found in {clean_dir}.'
    assert len(evil_tars) > 0, f'No evil tar files found in {evil_dir}.'

    clean_failed = []
    evil_failed = []

    # Preserve the original corpus checks.
    for tar in clean_tars:
        result = run_filter(tar)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(tar))

    for tar in evil_tars:
        result = run_filter(tar)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(tar))

    error_msg = []
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_tars)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_tars)} clean rejected: {', '.join(clean_failed)}")

    assert not evil_failed and not clean_failed, ' | '.join(error_msg)

    # Exercise newly generated archives at neutral, randomized paths. Their names and
    # paths do not disclose the expected result.
    with tempfile.TemporaryDirectory(prefix='wal_validation_') as workdir:
        cases = []
        for defect in [None, None, None, None, 'action', 'action', 'action', 'checksum', 'checksum', 'checksum']:
            path = os.path.join(workdir, uuid.uuid4().hex + '.tar')
            create_generated_archive(path, defect)
            cases.append((path, defect is None))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, should_accept in cases:
            result = run_filter(path)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append(
                    f'{os.path.basename(path)} expected '
                    f'{"status 0" if should_accept else "non-zero status"}, got {result.returncode}'
                )

        assert not failures, 'Generated archive validation failures: ' + '; '.join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
