#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import runpy
import shutil
import subprocess
import sys
import tarfile
import tempfile
import pytest

CONFIGS_DIR = "/home/user/configs"
NEW_MANIFEST = "/home/user/new_manifest.txt"
CONFIG_PATCH_TAR = "/home/user/config_patch.tar"
BASE_MANIFEST = "/home/user/base_manifest.txt"
ONE_MB = 1048576


def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)
    return sha256.hexdigest()


def config_state():
    state = {}
    for filename in os.listdir(CONFIGS_DIR):
        filepath = os.path.join(CONFIGS_DIR, filename)
        if os.path.isfile(filepath):
            state[filename] = (os.path.getsize(filepath), compute_sha256(filepath))
    return state


def find_scripts():
    scripts = []
    excluded = {NEW_MANIFEST, CONFIG_PATCH_TAR, BASE_MANIFEST}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__'}]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > ONE_MB:
                    continue
                with open(path, 'rb') as f:
                    first = f.readline(512).decode('utf-8', 'ignore').lower()
            except OSError:
                continue
            ext = os.path.splitext(name)[1].lower()
            language = None
            if ext == '.py' or ('python' in first and first.startswith('#!')):
                language = 'python'
            elif ext == '.pl' or ('perl' in first and first.startswith('#!')):
                language = 'perl'
            elif ext == '.rb' or ('ruby' in first and first.startswith('#!')):
                language = 'ruby'
            if language:
                scripts.append((path, language))
    return sorted(scripts, key=lambda item: os.path.getmtime(item[0]), reverse=True)


PYTHON_RUNNER = r'''
import mmap
import os
import runpy
import sys

script, marker = sys.argv[1], sys.argv[2]
real_mmap = mmap.mmap
used_large_config_mmap = False

def checked_mmap(fileno, *args, **kwargs):
    global used_large_config_mmap
    try:
        target = os.path.realpath('/proc/self/fd/%d' % fileno)
        if (target.startswith('/home/user/configs' + os.sep)
                and os.path.isfile(target)
                and os.fstat(fileno).st_size > 1048576):
            used_large_config_mmap = True
    except (OSError, TypeError, ValueError):
        pass
    return real_mmap(fileno, *args, **kwargs)

mmap.mmap = checked_mmap
sys.argv = [script]
exit_code = 0
try:
    runpy.run_path(script, run_name='__main__')
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_code = exc.code if isinstance(exc.code, int) else 1
finally:
    with open(marker, 'w') as f:
        f.write('1' if used_large_config_mmap else '0')
if exit_code:
    raise SystemExit(exit_code)
'''


def noncomment_source(path, language):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    if language in ('perl', 'ruby'):
        lines = [line.split('#', 1)[0] for line in lines]
    return '\n'.join(lines)


def run_script(path, language, marker):
    if language == 'python':
        command = [sys.executable, '-c', PYTHON_RUNNER, path, marker]
        return subprocess.run(command, cwd='/home/user', timeout=30,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True)
    source = noncomment_source(path, language)
    if language == 'perl':
        if not shutil.which('perl'):
            return None
        # Sys::Mmap's mmap call is the normal Perl mechanism for this task.
        if not re.search(r'\bSys::Mmap\b', source) or not re.search(r'\bmmap\s*\(', source):
            return None
        command = ['perl', path]
    else:
        if not shutil.which('ruby'):
            return None
        # Accept the standard IO::Buffer mapping API and common mmap bindings.
        if not (re.search(r'IO::Buffer\s*\.\s*map', source)
                or re.search(r'\bmmap\s*\(', source, re.I)
                or re.search(r'\bMmap\b', source)):
            return None
        command = ['ruby', path]
    result = subprocess.run(command, cwd='/home/user', timeout=30,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    if result.returncode == 0:
        with open(marker, 'w') as f:
            f.write('1')
    return result


def test_00_script_exists_runs_and_uses_mmap():
    scripts = find_scripts()
    assert scripts, 'No Python, Perl, or Ruby script was written under /home/user'

    original_configs = config_state()
    failures = []
    for path, language in scripts:
        for output in (NEW_MANIFEST, CONFIG_PATCH_TAR):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        fd, marker = tempfile.mkstemp(prefix='mmap-used-', dir='/tmp')
        os.close(fd)
        os.remove(marker)
        try:
            result = run_script(path, language, marker)
        except (subprocess.TimeoutExpired, OSError) as exc:
            failures.append(f'{path}: {exc}')
            continue

        if config_state() != original_configs:
            pytest.fail(f'Script {path} modified files in {CONFIGS_DIR}')
        if result is None:
            failures.append(f'{path}: unavailable interpreter or no executable mmap use')
            continue
        marker_value = ''
        if os.path.isfile(marker):
            with open(marker) as f:
                marker_value = f.read().strip()
            os.remove(marker)
        if (result.returncode == 0 and marker_value == '1'
                and os.path.isfile(NEW_MANIFEST)
                and os.path.isfile(CONFIG_PATCH_TAR)):
            return
        failures.append(f'{path}: exit={result.returncode}, mmap={marker_value}, stderr={result.stderr[-300:]}')

    pytest.fail('No submitted script successfully generated both artifacts while using mmap for a file over 1 MB. ' + '; '.join(failures))


def test_new_manifest_correctness():
    assert os.path.isfile(NEW_MANIFEST), f"New manifest not found at {NEW_MANIFEST}"

    # Compute expected manifest
    expected_lines = []
    for filename in os.listdir(CONFIGS_DIR):
        filepath = os.path.join(CONFIGS_DIR, filename)
        if os.path.isfile(filepath):
            file_hash = compute_sha256(filepath)
            expected_lines.append(f"{file_hash} {filename}")

    expected_lines.sort()
    expected_content = "\n".join(expected_lines) + "\n"

    with open(NEW_MANIFEST, 'r') as f:
        actual_content = f.read()

    # Standardize line endings just in case
    actual_lines = [line.strip() for line in actual_content.strip().split('\n') if line.strip()]
    expected_lines_clean = [line.strip() for line in expected_content.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines_clean, f"Manifest contents are incorrect. Expected:\n{expected_lines_clean}\nGot:\n{actual_lines}"


def test_config_patch_tar_contents():
    assert os.path.isfile(CONFIG_PATCH_TAR), f"Tar archive not found at {CONFIG_PATCH_TAR}"

    # Determine which files should be in the tar archive
    # Read base manifest
    base_hashes = {}
    if os.path.isfile(BASE_MANIFEST):
        with open(BASE_MANIFEST, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 2:
                    base_hashes[parts[1]] = parts[0]

    expected_files_in_tar = set()
    for filename in os.listdir(CONFIGS_DIR):
        filepath = os.path.join(CONFIGS_DIR, filename)
        if os.path.isfile(filepath):
            current_hash = compute_sha256(filepath)
            if filename not in base_hashes or base_hashes[filename] != current_hash:
                expected_files_in_tar.add(filename)

    # Explicitly reject compressed tar formats and require raw tar reading.
    with open(CONFIG_PATCH_TAR, 'rb') as f:
        signature = f.read(6)
    assert not signature.startswith(b'\x1f\x8b'), 'Archive must be an uncompressed tar, not gzip'
    assert not signature.startswith(b'BZh'), 'Archive must be an uncompressed tar, not bzip2'
    assert not signature.startswith(b'\xfd7zXZ\x00'), 'Archive must be an uncompressed tar, not xz'
    assert not signature.startswith(b'\x28\xb5\x2f\xfd'), 'Archive must be an uncompressed tar, not zstd'

    # Read tar archive
    try:
        with tarfile.open(CONFIG_PATCH_TAR, "r:") as tar:
            members = tar.getmembers()
            tar_members = tar.getnames()

            # Check that paths are relative (just the filename)
            actual_files_in_tar = set()
            for member in tar_members:
                assert "/" not in member and "\\" not in member, f"Tar archive contains directory paths or absolute paths: {member}. Expected just filenames."
                actual_files_in_tar.add(member)

            assert len(tar_members) == len(actual_files_in_tar), 'Tar archive contains duplicate member names'
            assert actual_files_in_tar == expected_files_in_tar, f"Tar archive contents mismatch. Expected {expected_files_in_tar}, got {actual_files_in_tar}"

            # Every expected member must be a regular file whose bytes match configs.
            for member in members:
                assert member.isfile(), f"Tar member {member.name} is not a regular file"
                source = os.path.join(CONFIGS_DIR, member.name)
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read tar member {member.name}"
                archived_hash = hashlib.sha256(extracted.read()).hexdigest()
                assert member.size == os.path.getsize(source), f"Tar member {member.name} has the wrong size"
                assert archived_hash == compute_sha256(source), f"Tar member {member.name} does not match {source}"
    except tarfile.ReadError:
        pytest.fail(f"Could not read {CONFIG_PATCH_TAR} as a valid uncompressed tar archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
