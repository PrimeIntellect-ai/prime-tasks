#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import shutil
import subprocess
import tempfile
import uuid
import zipfile

CONFIG_PATH = '/home/user/scan_config.ini'
ORIGINAL_REPORT = '/home/user/hidden_archives.log'


def read_report(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_hidden_archives_report_and_script_behavior():
    # Preserve the original report assertions.
    assert os.path.exists(ORIGINAL_REPORT), f"Report file {ORIGINAL_REPORT} was not created."

    expected_files = [
        ('/home/user/user_uploads/financials.csv', 'GZIP'),
        ('/home/user/user_uploads/notes.txt', 'GZIP'),
        ('/home/user/user_uploads/system_cache.dat', 'ZIP')
    ]

    expected_lines = []
    for filepath, archive_type in expected_files:
        assert os.path.exists(filepath), f"Expected file {filepath} is missing from the system."
        size = os.path.getsize(filepath)
        expected_lines.append(f"{filepath}|{archive_type}|{size}")
    expected_lines.sort()

    actual_lines = read_report(ORIGINAL_REPORT)
    assert actual_lines == expected_lines, (
        f"Report contents do not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )

    # Locate the Python artifact the agent was instructed to create.
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.git', '__pycache__', 'site-packages'}]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path) and os.path.getsize(path) <= 1024 * 1024:
                candidates.append(path)
    assert candidates, "No Python scanning script was found under /home/user."

    with open(CONFIG_PATH, 'rb') as f:
        saved_config = f.read()
    saved_report = None
    if os.path.exists(ORIGINAL_REPORT):
        with open(ORIGINAL_REPORT, 'rb') as f:
            saved_report = f.read()

    sandbox = tempfile.mkdtemp(prefix='archive_verify_', dir='/home/user')
    target = os.path.join(sandbox, 'random_uploads_' + uuid.uuid4().hex)
    report = os.path.join(sandbox, 'report_' + uuid.uuid4().hex + '.log')
    os.makedirs(target)

    try:
        # Random names prevent a fixed path/type table from satisfying this test.
        gzip_path = os.path.join(target, uuid.uuid4().hex + '.txt')
        zip_path = os.path.join(target, uuid.uuid4().hex + '.log')
        plain_path = os.path.join(target, uuid.uuid4().hex + '.gz')
        binary_path = os.path.join(target, uuid.uuid4().hex + '.dat')

        with gzip.open(gzip_path, 'wb') as f:
            f.write(os.urandom(8192))
        with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('payload.bin', os.urandom(6144))
        with open(plain_path, 'wb') as f:
            f.write(b'This has an archive-looking extension but plain contents.\n')
        with open(binary_path, 'wb') as f:
            f.write(b'\x00\x01\x02\x03' + os.urandom(128))

        with open(CONFIG_PATH, 'w') as f:
            f.write('[Scan]\n')
            f.write(f'target_directory = {target}\n')
            f.write(f'report_path = {report}\n')

        # Independently derive the answer by scanning every file and its header.
        dynamic_expected = []
        for entry in os.scandir(target):
            if not entry.is_file():
                continue
            with open(entry.path, 'rb') as f:
                header = f.read(4)
            archive_type = None
            if header.startswith(b'\x1f\x8b'):
                archive_type = 'GZIP'
            elif header.startswith(b'PK\x03\x04'):
                archive_type = 'ZIP'
            if archive_type:
                dynamic_expected.append(
                    f"{entry.path}|{archive_type}|{os.path.getsize(entry.path)}"
                )
        dynamic_expected.sort()

        successes = []
        errors = []
        for script in sorted(candidates):
            if os.path.exists(report):
                os.unlink(report)
            try:
                result = subprocess.run(
                    ['python3', script],
                    cwd=os.path.dirname(script) or '/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
            except Exception as exc:
                errors.append(f"{script}: {exc}")
                continue

            if result.returncode != 0:
                errors.append(f"{script}: exited {result.returncode}: {result.stderr[-300:]}")
                continue
            if not os.path.exists(report):
                errors.append(f"{script}: did not create configured report {report}")
                continue

            produced = read_report(report)
            if produced == dynamic_expected:
                successes.append(script)
            else:
                errors.append(
                    f"{script}: expected {dynamic_expected!r}, produced {produced!r}"
                )

        assert successes, (
            "No submitted Python script read the changed configuration and produced "
            "a header-derived report for randomized files. Attempts: " + '; '.join(errors)
        )
    finally:
        with open(CONFIG_PATH, 'wb') as f:
            f.write(saved_config)
        if saved_report is not None:
            with open(ORIGINAL_REPORT, 'wb') as f:
                f.write(saved_report)
        elif os.path.exists(ORIGINAL_REPORT):
            os.unlink(ORIGINAL_REPORT)
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
