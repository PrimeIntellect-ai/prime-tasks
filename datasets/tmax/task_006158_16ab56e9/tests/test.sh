#!/bin/bash
mkdir -p /logs/verifier

run_tests() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_script_exists_and_executable():
    script_path = "/home/user/audit_backups.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_quarantine_directory_exists():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Quarantine directory {quarantine_dir} does not exist."

def test_quarantine_symlinks():
    expected_symlinks = {
        "/home/user/quarantine/system.tar.gz": "/home/user/backups/server_alpha/system.tar.gz",
        "/home/user/quarantine/data.tar.gz": "/home/user/backups/server_beta/archive/data.tar.gz",
    }

    for symlink_path, target_path in expected_symlinks.items():
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}."

def test_quarantine_log():
    log_path = "/home/user/quarantine_log.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        log_content = f.read().splitlines()

    expected_lines = [
        "VULNERABLE: /home/user/backups/server_alpha/system.tar.gz -> var/log/../../../etc/shadow",
        "VULNERABLE: /home/user/backups/server_beta/archive/data.tar.gz -> ../.ssh/authorized_keys"
    ]

    for expected_line in expected_lines:
        assert expected_line in log_content, f"Expected log entry not found: {expected_line}"

    vulnerable_lines = [line for line in log_content if line.startswith("VULNERABLE:")]
    assert len(vulnerable_lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} VULNERABLE lines, found {len(vulnerable_lines)}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 << 'PY_EOF' || return 1
import os
import tarfile
import uuid

 token = uuid.uuid4().hex
PY_EOF
}

# Replace the probe creator above with a syntactically isolated implementation.
run_all_tests() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_script_exists_and_executable():
    script_path = "/home/user/audit_backups.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_quarantine_directory_exists():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Quarantine directory {quarantine_dir} does not exist."

def test_quarantine_symlinks():
    expected_symlinks = {
        "/home/user/quarantine/system.tar.gz": "/home/user/backups/server_alpha/system.tar.gz",
        "/home/user/quarantine/data.tar.gz": "/home/user/backups/server_beta/archive/data.tar.gz",
    }
    for symlink_path, target_path in expected_symlinks.items():
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}."

def test_quarantine_log():
    log_path = "/home/user/quarantine_log.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        log_content = f.read().splitlines()
    expected_lines = [
        "VULNERABLE: /home/user/backups/server_alpha/system.tar.gz -> var/log/../../../etc/shadow",
        "VULNERABLE: /home/user/backups/server_beta/archive/data.tar.gz -> ../.ssh/authorized_keys"
    ]
    for expected_line in expected_lines:
        assert expected_line in log_content, f"Expected log entry not found: {expected_line}"
    vulnerable_lines = [line for line in log_content if line.startswith("VULNERABLE:")]
    assert len(vulnerable_lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} VULNERABLE lines, found {len(vulnerable_lines)}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 << 'PY_EOF' || return 1
import os
import tarfile
import uuid

token = uuid.uuid4().hex
probe_dir = os.path.join('/home/user/backups', 'dynamic probe ' + token)
os.makedirs(os.path.join(probe_dir, 'nested'), exist_ok=False)

safe_path = os.path.join(probe_dir, 'safe_' + token + '.tar.gz')
with tarfile.open(safe_path, 'w:gz') as archive:
    for name in ('ordinary/file.txt', 'another/safe_file'):
        info = tarfile.TarInfo(name=name)
        info.size = 0
        archive.addfile(info)

bad_path = os.path.join(probe_dir, 'nested', 'compromised_' + token + '.tar.gz')
with tarfile.open(bad_path, 'w:gz') as archive:
    for name in (
        'ordinary.txt',
        'directory/../../escape_' + token,
        '../later_' + token,
    ):
        info = tarfile.TarInfo(name=name)
        info.size = 0
        archive.addfile(info)
PY_EOF

    rm -rf /home/user/quarantine
    rm -f /home/user/quarantine_log.txt

    runuser -u user -- timeout 30s /home/user/audit_backups.sh || return 1

    cat << 'TEST_EOF' > /tmp/test_behavior.py
import collections
import os
import tarfile

BACKUPS = "/home/user/backups"
QUARANTINE = "/home/user/quarantine"
LOG = "/home/user/quarantine_log.txt"
SCRIPT = "/home/user/audit_backups.sh"


def expected_results():
    expected = {}
    for root, _, files in os.walk(BACKUPS):
        for filename in files:
            if not filename.endswith('.tar.gz'):
                continue
            archive_path = os.path.abspath(os.path.join(root, filename))
            with tarfile.open(archive_path, 'r:gz') as archive:
                suspicious = next((member.name for member in archive.getmembers()
                                   if '../' in member.name), None)
            if suspicious is not None:
                assert filename not in expected, "Test archives unexpectedly have colliding basenames"
                expected[filename] = (archive_path, suspicious)
    return expected


def test_artifact_is_an_executable_bash_script():
    assert os.path.isfile(SCRIPT)
    assert os.access(SCRIPT, os.X_OK)
    with open(SCRIPT, 'rb') as script:
        first_line = script.readline().decode('utf-8', errors='replace').lower()
    assert first_line.startswith('#!') and 'bash' in first_line, "Script must use a Bash shebang"


def test_fresh_execution_generated_complete_results():
    expected = expected_results()
    assert os.path.isdir(QUARANTINE)
    assert os.path.isfile(LOG)

    actual_entries = set(os.listdir(QUARANTINE))
    assert actual_entries == set(expected), "Quarantine must contain exactly the vulnerable archive links"

    for basename, (archive_path, _) in expected.items():
        link_path = os.path.join(QUARANTINE, basename)
        assert os.path.islink(link_path), f"{link_path} is not a symbolic link"
        target = os.readlink(link_path)
        assert os.path.isabs(target), f"{link_path} does not use an absolute target"
        assert target == archive_path, f"{link_path} points to {target}, expected {archive_path}"

    with open(LOG, 'r', encoding='utf-8') as log_file:
        actual_lines = log_file.read().splitlines()
    expected_lines = [
        f"VULNERABLE: {archive_path} -> {suspicious}"
        for archive_path, suspicious in expected.values()
    ]
    assert collections.Counter(actual_lines) == collections.Counter(expected_lines)
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_behavior.py -x --tb=short || return 1
}

if run_all_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
