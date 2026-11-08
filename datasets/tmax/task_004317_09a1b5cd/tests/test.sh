#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid


def canonical_tar_name(name):
    assert not name.startswith('/'), f"Archive member uses an absolute path: {name}"
    parts = [part for part in name.split('/') if part not in ('', '.')]
    assert '..' not in parts, f"Archive member escapes the watched directory: {name}"
    return '/'.join(parts)


def test_trigger_log_content():
    """Verify that the trigger log exists and contains the correct trigger file path."""
    log_path = '/home/user/trigger.log'
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_path = '/home/user/workdir/subdir/trigger.txt'
    assert content == expected_path, f"Expected {log_path} to contain '{expected_path}', but got '{content}'."


def test_archive_exists_and_valid():
    """Verify that the snapshot archive exists and is a valid tar.gz file."""
    archive_path = '/home/user/snapshot.tar.gz'
    assert os.path.exists(archive_path), f"{archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar file."


def test_archive_contents():
    """Verify that the snapshot archive contains the correct files and contents."""
    archive_path = '/home/user/snapshot.tar.gz'

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()
        initial_member = None
        trigger_member = None

        for name in names:
            if name.endswith('initial.txt'):
                initial_member = name
            if name.endswith('trigger.txt'):
                trigger_member = name

        assert initial_member is not None, "initial.txt not found in the archive."
        assert trigger_member is not None, "trigger.txt not found in the archive."

        f_init = tar.extractfile(initial_member)
        assert f_init is not None, f"Could not extract {initial_member}"
        init_content = f_init.read().decode('utf-8').strip()
        assert init_content == "INIT", f"Expected initial.txt to contain 'INIT', got '{init_content}'"

        f_trig = tar.extractfile(trigger_member)
        assert f_trig is not None, f"Could not extract {trigger_member}"
        trig_content = f_trig.read().decode('utf-8').strip()
        assert trig_content == "BACKUP_ME", f"Expected trigger.txt to contain 'BACKUP_ME', got '{trig_content}'"


def test_archive_paths_are_relative():
    with tarfile.open('/home/user/snapshot.tar.gz', 'r:gz') as tar:
        normalized = [canonical_tar_name(member.name) for member in tar.getmembers()]
    assert 'initial.txt' in normalized
    assert 'subdir/trigger.txt' in normalized


def test_go_source_code():
    """Verify that the Go source code exists and uses required packages."""
    main_go_path = '/home/user/archiver/main.go'
    assert os.path.exists(main_go_path), f"{main_go_path} does not exist."

    with open(main_go_path, 'r') as f:
        content = f.read()

    assert 'fsnotify' in content, "The Go program must use the 'fsnotify' package."
    assert 'archive/tar' in content, "The Go program must use the 'archive/tar' package."
    assert 'compress/gzip' in content, "The Go program must use the 'compress/gzip' package."


def test_program_reacts_to_unpredictable_recursive_event():
    token = uuid.uuid4().hex
    watched = tempfile.mkdtemp(prefix='archiver-watch-')
    nested = os.path.join(watched, 'nested_' + token)
    os.mkdir(nested)

    initial_name = 'initial_' + token + '.txt'
    trigger_name = 'trigger_' + token + '.txt'
    initial_content = ('INITIAL_' + token).encode()
    trigger_content = ('TRIGGER_' + token).encode()
    initial_path = os.path.join(watched, initial_name)
    trigger_path = os.path.join(nested, trigger_name)

    with open(initial_path, 'wb') as f:
        f.write(initial_content)

    binary = '/tmp/auto_archiver_' + token
    stage_path = '/tmp/archiver_stage_' + token
    proc = None
    try:
        build = subprocess.run(
            ['go', 'build', '-o', binary, '.'],
            cwd='/home/user/archiver',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"Go program did not build:\n{build.stderr}"

        for output in ('/home/user/snapshot.tar.gz', '/home/user/trigger.log'):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        proc = subprocess.Popen([binary, watched], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1.0)
        assert proc.poll() is None, "Program exited before a Create or Write event occurred"

        with open(stage_path, 'wb') as f:
            f.write(trigger_content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(stage_path, trigger_path)

        deadline = time.time() + 15
        while proc.poll() is None and time.time() < deadline:
            time.sleep(0.1)
        assert proc.poll() is not None, "Program did not exit after the recursive Create event"
        stdout, stderr = proc.communicate(timeout=2)
        assert proc.returncode == 0, f"Program exited with {proc.returncode}: {stderr.decode(errors='replace')}"

        with open('/home/user/trigger.log', 'r') as f:
            assert f.read().strip() == trigger_path

        with tarfile.open('/home/user/snapshot.tar.gz', 'r:gz') as tar:
            members = {}
            for member in tar.getmembers():
                normalized = canonical_tar_name(member.name)
                if normalized:
                    members[normalized] = member

            expected_initial = initial_name
            expected_trigger = 'nested_' + token + '/' + trigger_name
            assert expected_initial in members, f"Missing relative archive member {expected_initial}"
            assert expected_trigger in members, f"Missing relative archive member {expected_trigger}"

            initial_file = tar.extractfile(members[expected_initial])
            trigger_file = tar.extractfile(members[expected_trigger])
            assert initial_file is not None and initial_file.read() == initial_content
            assert trigger_file is not None and trigger_file.read() == trigger_content
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        shutil.rmtree(watched, ignore_errors=True)
        for path in (binary, stage_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
