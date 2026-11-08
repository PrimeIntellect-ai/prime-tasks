#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import io
import os
import pwd
import shutil
import subprocess
import tarfile
import time
import uuid


def test_update_log_contents():
    """Verify the log file exists and contains exactly the expected safe paths."""
    log_path = '/home/user/update_log.txt'
    assert os.path.exists(log_path), f"Log file {log_path} was not created."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_paths = {
        '/home/user/docs/valid1.md',
        '/home/user/docs/subdir/valid2.md'
    }

    assert set(lines) == expected_paths, f"Log file contents incorrect. Expected {expected_paths}, got {set(lines)}."
    assert len(lines) == 2, "Log file should contain exactly two lines for the two safely extracted files."


def test_script_uses_locking():
    """Verify the script contains the required locking mechanisms."""
    script_path = '/home/user/process_updates.py'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."

    with open(script_path, 'r') as f:
        content = f.read()

    assert 'fcntl.flock' in content, "Script does not appear to use fcntl.flock for concurrent-safe logging."
    assert 'fcntl.LOCK_EX' in content, "Script does not appear to use fcntl.LOCK_EX for exclusive locking."


def test_valid1_content():
    """Verify valid1.md was extracted and correctly tagged."""
    path = '/home/user/docs/valid1.md'
    assert os.path.exists(path), f"File {path} was not extracted."

    with open(path, 'r') as f:
        content = f.read()

    assert content.startswith("<!-- REVIEWED -->\n"), f"{path} does not start with the required REVIEWED tag."
    assert "Content of valid1" in content, f"{path} original content is missing or corrupted."


def test_valid2_content():
    """Verify valid2.md was extracted and correctly tagged."""
    path = '/home/user/docs/subdir/valid2.md'
    assert os.path.exists(path), f"File {path} was not extracted."

    with open(path, 'r') as f:
        content = f.read()

    assert content.startswith("<!-- REVIEWED -->\n"), f"{path} does not start with the required REVIEWED tag."
    assert "Content of valid2" in content, f"{path} original content is missing or corrupted."


def test_old_doc_unchanged():
    """Verify that older, existing documentation was not tagged."""
    path = '/home/user/docs/existing/old_doc.md'
    assert os.path.exists(path), f"Existing file {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    assert "<!-- REVIEWED -->" not in content, f"Old documentation at {path} should not have been tagged."
    # setup used echo without -e, so the backslash-n is literal text.
    assert "Old Documentation\\nLine 2" in content, f"Original content of {path} was altered."


def test_path_traversal_prevented():
    """Verify that malicious path traversal payloads were successfully skipped."""
    bad_paths = [
        '/home/user/escaped.md',
        '/home/user/docs/escaped.md',
        '/home/user/absolute.md'
    ]

    for bad_path in bad_paths:
        assert not os.path.exists(bad_path), f"Path traversal vulnerability detected! Malicious file {bad_path} was extracted."


def _remove(path):
    if not os.path.lexists(path):
        return
    if os.path.islink(path) or not os.path.isdir(path):
        os.unlink(path)
    else:
        shutil.rmtree(path)


def _add_file(tar, name, data, mtime):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = mtime
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def test_script_behavior_on_fresh_unpredictable_archive():
    """Execute the submitted artifact against randomized inputs and a contended log."""
    token = uuid.uuid4().hex
    docs = '/home/user/docs'
    archive = '/home/user/updates.tar'
    log = '/home/user/update_log.txt'
    backups = {
        docs: f'/tmp/docs-{token}',
        archive: f'/tmp/updates-{token}.tar',
        log: f'/tmp/update-log-{token}.txt',
    }

    safe_root = f'note_{token}.md'
    safe_nested = f'area_{token}/nested_{token}.md'
    safe_text = f'area_{token}/plain_{token}.txt'
    escaped = f'escape_{token}.md'
    absolute = f'absolute_{token}.md'
    sneaky = f'sneaky_{token}.md'
    bad_paths = [
        f'/home/user/{escaped}',
        f'/home/user/{absolute}',
        f'/home/user/docs/{sneaky}',
    ]
    old_rel = f'existing_{token}/old_{token}.md'
    old_content = f'preexisting-{token}\\nunchanged\n'.encode()
    payloads = {
        safe_root: f'root-{token}\n'.encode(),
        safe_nested: f'nested-{token}\n'.encode(),
        safe_text: f'text-{token}\n'.encode(),
    }

    for original, backup in backups.items():
        assert os.path.lexists(original), f"Required original path disappeared before behavioral test: {original}"
        os.rename(original, backup)

    proc = None
    lock_handle = None
    try:
        os.makedirs(os.path.join(docs, os.path.dirname(old_rel)), exist_ok=True)
        old_path = os.path.join(docs, old_rel)
        with open(old_path, 'wb') as f:
            f.write(old_content)
        old_time = time.time() - 2 * 24 * 60 * 60
        os.utime(old_path, (old_time, old_time))

        now = int(time.time())
        with tarfile.open(archive, 'w') as tar:
            for name, data in payloads.items():
                _add_file(tar, name, data, now)
            _add_file(tar, f'../{escaped}', b'escape\n', now)
            _add_file(tar, f'/home/user/{absolute}', b'absolute\n', now)
            _add_file(tar, f'folder_{token}/../{sneaky}', b'sneaky\n', now)

        user = pwd.getpwnam('user')
        for root, dirs, files in os.walk(docs):
            os.chown(root, user.pw_uid, user.pw_gid)
            for name in dirs + files:
                os.chown(os.path.join(root, name), user.pw_uid, user.pw_gid)
        os.chown(archive, user.pw_uid, user.pw_gid)

        with open(log, 'w'):
            pass
        os.chown(log, user.pw_uid, user.pw_gid)
        lock_handle = open(log, 'a+')
        fcntl.flock(lock_handle, fcntl.LOCK_EX)

        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        proc = subprocess.Popen(
            ['python3', '/home/user/process_updates.py'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=demote,
        )
        time.sleep(0.5)
        assert proc.poll() is None, "Script completed while another process held the exclusive log lock."

        fcntl.flock(lock_handle, fcntl.LOCK_UN)
        lock_handle.close()
        lock_handle = None
        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, f"Script failed on a fresh archive. stdout={stdout!r}, stderr={stderr!r}"

        tag = b'<!-- REVIEWED -->\n'
        for rel in (safe_root, safe_nested):
            destination = os.path.join(docs, rel)
            assert os.path.isfile(destination), f"Safe archive member was not extracted: {rel}"
            with open(destination, 'rb') as f:
                assert f.read() == tag + payloads[rel], f"Markdown member was not extracted and tagged correctly: {rel}"

        text_destination = os.path.join(docs, safe_text)
        assert os.path.isfile(text_destination), "Safe non-Markdown member was not extracted."
        with open(text_destination, 'rb') as f:
            assert f.read() == payloads[safe_text], "Non-Markdown member was incorrectly modified."

        with open(old_path, 'rb') as f:
            assert f.read() == old_content, "Old pre-existing Markdown documentation was modified."

        expected_log = {
            os.path.join(docs, safe_root),
            os.path.join(docs, safe_nested),
            os.path.join(docs, safe_text),
        }
        with open(log, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == len(expected_log), f"Expected one log entry per extracted file, got {lines!r}"
        assert set(lines) == expected_log, f"Log did not contain the derived safe destinations: {lines!r}"

        for bad_path in bad_paths:
            assert not os.path.lexists(bad_path), f"Unsafe randomized archive member escaped extraction: {bad_path}"
    finally:
        if lock_handle is not None:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)
            lock_handle.close()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        for path in bad_paths:
            _remove(path)
        for original in backups:
            _remove(original)
        for original, backup in backups.items():
            if os.path.lexists(backup):
                os.rename(backup, original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
