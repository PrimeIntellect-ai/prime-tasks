#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import subprocess
import zipfile

HOME = '/home/user'
CLEAN = '/home/user/clean_data'
ARCHIVE = '/home/user/incoming/data.zip'
DETECTED = '/home/user/zip_slip_detected.txt'


def test_culprit_file():
    culprit_path = '/home/user/culprit.txt'
    assert os.path.isfile(culprit_path), f"File {culprit_path} does not exist."

    with open(culprit_path, 'r') as f:
        content = f.read().strip()

    assert content == "researcher_89", f"Expected culprit to be 'researcher_89', but got '{content}'"


def test_clean_data_extracted():
    clean_data_dir = '/home/user/clean_data'
    assert os.path.isdir(clean_data_dir), f"Directory {clean_data_dir} does not exist."

    expected_files = {
        'dataset_info.txt',
        'images/img1.png',
        'images/img2.png'
    }

    actual_files = set()
    for root, dirs, files in os.walk(clean_data_dir):
        assert not any(os.path.islink(os.path.join(root, d)) for d in dirs), "Symlinks are not allowed in clean_data"
        for file in files:
            full_path = os.path.join(root, file)
            assert not os.path.islink(full_path), f"Extracted file is a symlink: {full_path}"
            rel_path = os.path.relpath(full_path, clean_data_dir)
            actual_files.add(rel_path)

    assert actual_files == expected_files, f"Expected safe files {expected_files} in {clean_data_dir}, but found {actual_files}"

    expected_contents = {
        'dataset_info.txt': b'This is a clean dataset.',
        'images/img1.png': '\x89PNG\r\n\x1a\n\x00\x00'.encode('utf-8'),
        'images/img2.png': '\x89PNG\r\n\x1a\n\x00\x00'.encode('utf-8'),
    }
    for rel_path, expected in expected_contents.items():
        with open(os.path.join(clean_data_dir, rel_path), 'rb') as f:
            actual = f.read()
        assert actual == expected, f"Incorrect contents in extracted file {rel_path}"


def test_zip_slip_detected():
    detected_path = '/home/user/zip_slip_detected.txt'
    assert os.path.isfile(detected_path), f"File {detected_path} does not exist."

    expected_malicious_paths = {
        '../../../home/user/.ssh/authorized_keys',
        'images/../../etc/shadow',
        '/absolute/path/malware.sh'
    }

    with open(detected_path, 'r') as f:
        lines = f.read().splitlines()

    actual_paths = {line.strip() for line in lines if line.strip()}

    assert actual_paths == expected_malicious_paths, f"Expected malicious paths {expected_malicious_paths}, but got {actual_paths}"


def test_original_unsafe_entries_were_not_extracted():
    unsafe_destinations = [
        '/home/user/.ssh/authorized_keys',
        '/home/user/etc/shadow',
        '/absolute/path/malware.sh',
    ]
    for path in unsafe_destinations:
        assert not os.path.lexists(path), f"Unsafe archive entry was written outside clean_data: {path}"


def _python_candidates():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if os.path.join(root, d) not in {CLEAN, '/home/user/incoming'}]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path) and not os.path.islink(path):
                candidates.append(path)
    return sorted(candidates)


def _clear_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def _run_as_user(script):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        ['python3', script],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        preexec_fn=demote,
    )


def _dynamic_result_is_correct(safe_entries, malicious_names, escape_paths):
    if not os.path.isdir(CLEAN) or not os.path.isfile(DETECTED):
        return False

    actual_files = set()
    for root, dirs, files in os.walk(CLEAN):
        if any(os.path.islink(os.path.join(root, d)) for d in dirs):
            return False
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                return False
            actual_files.add(os.path.relpath(path, CLEAN))

    if actual_files != set(safe_entries):
        return False
    for rel_path, expected_content in safe_entries.items():
        with open(os.path.join(CLEAN, rel_path), 'rb') as f:
            if f.read() != expected_content:
                return False

    with open(DETECTED, 'r') as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]
    if len(lines) != len(malicious_names) or set(lines) != set(malicious_names):
        return False

    return not any(os.path.lexists(path) for path in escape_paths)


def test_python_processor_handles_unseen_archive_safely():
    candidates = _python_candidates()
    assert candidates, "No Python archive-processing script was written under /home/user"

    token = secrets.token_hex(8)
    safe_entries = {
        f'records_{token}/part_{token}.bin': secrets.token_bytes(37),
        f'notes_{token}.txt': secrets.token_bytes(23),
    }
    malicious_entries = {
        f'../verifier_escape_{token}.txt': b'escape-one',
        f'safe_dir/../../verifier_escape2_{token}.txt': b'escape-two',
        f'/home/user/verifier_abs_{token}.txt': b'escape-three',
    }
    escape_paths = [
        f'/home/user/verifier_escape_{token}.txt',
        f'/home/user/verifier_escape2_{token}.txt',
        f'/home/user/verifier_abs_{token}.txt',
    ]

    errors = []
    for script in candidates:
        _clear_path(CLEAN)
        if os.path.lexists(DETECTED):
            _clear_path(DETECTED)
        for path in escape_paths:
            if os.path.lexists(path):
                _clear_path(path)

        with zipfile.ZipFile(ARCHIVE, 'w') as zf:
            for name, content in safe_entries.items():
                zf.writestr(name, content)
            for name, content in malicious_entries.items():
                zf.writestr(name, content)

        try:
            result = _run_as_user(script)
        except (subprocess.TimeoutExpired, OSError) as exc:
            errors.append(f'{script}: {exc}')
            continue

        if result.returncode == 0 and _dynamic_result_is_correct(
            safe_entries, list(malicious_entries), escape_paths
        ):
            return

        errors.append(
            f"{script}: exit={result.returncode}, stderr={result.stderr.decode('utf-8', 'replace')[-500:]}"
        )

    assert False, "No submitted Python script securely processed an unseen archive. " + " | ".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
