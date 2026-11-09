#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import subprocess
import time
import uuid


def test_archived_logs_exists_and_content():
    archive_path = '/home/user/archived_logs.bak'
    assert os.path.exists(archive_path), f"Archive file {archive_path} not found."

    with open(archive_path, 'r') as f:
        archive_contents = f.read()

    expected_snippets = [
        "--- /home/user/data/logs/app1/db.log ---\nerror at line 1\nerror at line 2\n",
        "--- /home/user/data/logs/app2/auth.log ---\nlogin success user admin\nlogin failed user test\n",
        "--- /home/user/data/logs/app2/nested/build.log ---\ncompilation finished\n"
    ]

    for snippet in expected_snippets:
        assert snippet in archive_contents, f"Missing or incorrectly formatted snippet in archive:\n{snippet}"

    assert "server.log" not in archive_contents, "Active log server.log was incorrectly archived."
    assert "metrics.log" not in archive_contents, "Active log metrics.log was incorrectly archived."


def test_inactive_logs_truncated():
    inactive_logs = [
        '/home/user/data/logs/app1/db.log',
        '/home/user/data/logs/app2/auth.log',
        '/home/user/data/logs/app2/nested/build.log'
    ]
    for log in inactive_logs:
        assert os.path.exists(log), f"Log file {log} was deleted instead of truncated."
        assert os.path.getsize(log) == 0, f"Inactive log file {log} was not truncated to 0 bytes."


def test_active_logs_unmodified():
    active_logs = {
        "/home/user/data/logs/app1/server.log": "writing active data...\n",
        "/home/user/data/logs/app2/nested/metrics.log": "metric stream\n"
    }
    for filepath, expected_content in active_logs.items():
        assert os.path.exists(filepath), f"Active log file {filepath} is missing."
        assert os.path.getsize(filepath) > 0, f"Active log file {filepath} was incorrectly truncated."
        with open(filepath, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content of active log {filepath} was modified."


def test_script_uses_fcntl():
    script_path = '/home/user/reclaimer.py'
    assert os.path.exists(script_path), f"Script {script_path} not found."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
    with open(script_path, 'r') as f:
        code = f.read()
    assert 'fcntl.flock' in code or 'fcntl' in code, f"The script {script_path} does not use fcntl for locking."


def test_script_recursively_discovers_logs_honors_locks_and_really_flocks():
    script_path = '/home/user/reclaimer.py'
    archive_path = '/home/user/archived_logs.bak'
    token = uuid.uuid4().hex
    fixture_dir = os.path.join('/home/user/data/logs', 'verification_' + token, 'deep', 'nested')
    inactive_path = os.path.join(fixture_dir, 'inactive_' + token + '.log')
    active_path = os.path.join(fixture_dir, 'active_' + token + '.log')
    active_lock = active_path + '.lock'
    inactive_contents = ('dynamic inactive payload ' + token).encode()
    active_contents = ('dynamic active payload ' + token + '\n').encode()

    # Prevent already-processed fixture logs from being re-archived during this run,
    # leaving the new randomly named log as the only inactive input.
    existing_inactive = [
        '/home/user/data/logs/app1/db.log',
        '/home/user/data/logs/app2/auth.log',
        '/home/user/data/logs/app2/nested/build.log'
    ]
    temporary_locks = [path + '.lock' for path in existing_inactive]

    os.makedirs(fixture_dir, exist_ok=False)
    with open(inactive_path, 'wb') as f:
        f.write(inactive_contents)
    with open(active_path, 'wb') as f:
        f.write(active_contents)
    open(active_lock, 'wb').close()
    for path in temporary_locks:
        open(path, 'wb').close()

    process = None
    try:
        with open(archive_path, 'a+b') as held_archive:
            held_archive.flush()
            with open(archive_path, 'rb') as f:
                archive_before = f.read()

            # A genuine exclusive flock in reclaimer.py must block while this lock
            # is held. It must also not truncate the input before archiving it.
            fcntl.flock(held_archive.fileno(), fcntl.LOCK_EX)
            process = subprocess.Popen(
                ['python3', script_path],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            time.sleep(1.0)
            blocked_while_locked = process.poll() is None
            with open(archive_path, 'rb') as f:
                archive_during_lock = f.read()
            with open(inactive_path, 'rb') as f:
                inactive_during_lock = f.read()
            fcntl.flock(held_archive.fileno(), fcntl.LOCK_UN)

        try:
            stdout, stderr = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
            raise AssertionError('reclaimer.py did not finish after the archive lock was released')

        assert blocked_while_locked, 'reclaimer.py did not block on an exclusive lock held on the archive.'
        assert archive_during_lock == archive_before, 'The archive was modified without acquiring its exclusive lock.'
        assert inactive_during_lock == inactive_contents, 'The inactive log was truncated before its contents were safely archived.'
        assert process.returncode == 0, f"reclaimer.py failed:\nstdout:\n{stdout}\nstderr:\n{stderr}"

        assert os.path.exists(inactive_path), 'The dynamically discovered inactive log was deleted.'
        assert os.path.getsize(inactive_path) == 0, 'The dynamically discovered inactive log was not truncated.'
        with open(active_path, 'rb') as f:
            assert f.read() == active_contents, 'A dynamically named log with a corresponding lock file was modified.'

        with open(archive_path, 'rb') as f:
            archive_after = f.read()
        expected_append = (
            ('--- ' + inactive_path + ' ---\n').encode()
            + inactive_contents
            + b'\n'
        )
        assert archive_after[len(archive_before):] == expected_append, (
            'The recursively discovered log was not appended using the exact required format, '
            'or a locked log was also archived.'
        )
        assert active_path.encode() not in archive_after, 'The dynamically named active log was archived.'
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        for path in temporary_locks:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
