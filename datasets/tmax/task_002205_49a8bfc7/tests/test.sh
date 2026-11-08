#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import uuid
import pytest

SCRIPT_PATH = '/home/user/safe_backup.sh'
LOG_PATH = '/home/user/backup.log'
EXCLUDE_PATH = '/home/user/exclude.txt'
TAR_PATH = '/home/user/safe_backup.tar.gz'
TOKEN = uuid.uuid4().hex
DYNAMIC_EXCLUDED = f'/home/user/data/audit_excluded_{TOKEN}'
DYNAMIC_INCLUDED = f'/home/user/data/audit_included_{TOKEN}'


def get_expected_excludes(log_path):
    if not os.path.exists(log_path):
        return []

    with open(log_path, 'r') as f:
        content = f.read()

    excludes = []
    blocks = content.split('--BEGIN--')
    for block in blocks:
        if not block.strip():
            continue

        target = None
        has_symlink_loop = False

        for line in block.splitlines():
            line = line.strip()
            if line.startswith('Target:'):
                target = line.split('Target:', 1)[1].strip()
            elif line.startswith('Details:') and 'Symlink loop' in line:
                has_symlink_loop = True

        if target and has_symlink_loop:
            excludes.append(target)

    return sorted(excludes)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_executes_and_handles_fresh_inputs():
    os.makedirs(DYNAMIC_EXCLUDED, exist_ok=False)
    os.makedirs(DYNAMIC_INCLUDED, exist_ok=False)

    with open(os.path.join(DYNAMIC_EXCLUDED, 'must_not_archive.txt'), 'w') as f:
        f.write('excluded probe\n')
    with open(os.path.join(DYNAMIC_INCLUDED, 'must_archive.txt'), 'w') as f:
        f.write('included probe\n')

    with open(LOG_PATH, 'a') as f:
        f.write(f'''\n--BEGIN--
Target: {DYNAMIC_EXCLUDED}
Status: ERROR
Details: Runtime probe: Symlink loop encountered
--END--
--BEGIN--
Target: {DYNAMIC_INCLUDED}
Status: ERROR
Details: Runtime probe: symlink loop in lower case only
--END--
''')

    for path in (EXCLUDE_PATH, TAR_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def test_exclude_file_correct():
    assert os.path.isfile(EXCLUDE_PATH), f"Exclude file {EXCLUDE_PATH} does not exist."

    with open(EXCLUDE_PATH, 'r') as f:
        actual_excludes = sorted([line.strip() for line in f if line.strip()])

    expected_excludes = get_expected_excludes(LOG_PATH)

    assert actual_excludes == expected_excludes, f"Exclude file contents are incorrect. Expected {expected_excludes}, got {actual_excludes}."


def test_tarball_exists_and_valid():
    assert os.path.isfile(TAR_PATH), f"Archive {TAR_PATH} does not exist."
    assert tarfile.is_tarfile(TAR_PATH), f"Archive {TAR_PATH} is not a valid tarball."


def test_tarball_contents():
    if not os.path.isfile(TAR_PATH) or not tarfile.is_tarfile(TAR_PATH):
        pytest.skip("Tarball missing or invalid")

    expected_excludes = get_expected_excludes(LOG_PATH)

    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        members = tar.getnames()

    # Check that normal files are included.
    # Tar might strip leading slashes, so we check for the suffix.
    expected_files = [
        'home/user/data/docs/file1.txt',
        'home/user/data/docs/file2.txt',
        'home/user/data/images/pic.jpg',
        f'home/user/data/audit_included_{TOKEN}/must_archive.txt',
    ]

    for ef in expected_files:
        found = any(m.endswith(ef) for m in members)
        assert found, f"Expected file {ef} is missing from the archive."

    # Check that excluded directories are NOT included.
    for exc in expected_excludes:
        exc_stripped = exc.lstrip('/')

        for m in members:
            m_stripped = m.lstrip('/')
            assert not m_stripped.startswith(exc_stripped), f"Excluded path {exc} was found in the archive as {m}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
