#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time

SCRIPT_PATH = '/home/user/archive_config.py'
ARCHIVE_PATH = '/home/user/archived_settings.conf'
RULE_PATH = '/home/user/backup_rule.json'
SOURCE_PATH = '/home/user/settings.conf'


def test_archived_settings_exists_and_redacted():
    archived_path = ARCHIVE_PATH
    assert os.path.isfile(archived_path), f"The file {archived_path} was not created."

    with open(archived_path, 'r') as f:
        content = f.read()

    expected_lines = [
        "USER=admin",
        "DEBUG=true",
        "LOG_LEVEL=info",
        "SECRET_TOKEN=***",
        "DATABASE_URL=postgres://localhost",
        "SECRET_TOKEN_EXTRA=skip"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' missing or incorrect in {archived_path}."

    assert "super_secret_12345" not in content, "The secret token was not redacted in the archive file."

    expected = (
        "USER=admin\n"
        "DEBUG=true\n"
        "LOG_LEVEL=info\n"
        "SECRET_TOKEN=***\n"
        "DATABASE_URL=postgres://localhost\n"
        "SECRET_TOKEN_EXTRA=skip\n"
    )
    assert content == expected, "The archive does not exactly match the required transformed source."

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"The script failed when executed: {result.stderr}"
    assert result.stdout == content, "The archive is not the exact stdout produced by the script."


def test_archive_config_script_exists_and_uses_flock():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"The script {script_path} was not created."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "fcntl.flock" in content, "The script does not appear to use 'fcntl.flock'."
    assert "LOCK_SH" in content, "The script does not appear to use 'LOCK_SH' for a shared lock."


def test_script_uses_rule_and_really_acquires_shared_lock():
    with open(RULE_PATH, 'rb') as f:
        original_rule = f.read()

    token = secrets.token_hex(8).upper()
    mask_key = f"PRIVATE_{token}"

    with tempfile.TemporaryDirectory() as workdir:
        source_path = os.path.join(workdir, f"source-{secrets.token_hex(8)}.conf")
        event_path = os.path.join(workdir, 'flock-events.log')
        shim_dir = os.path.join(workdir, 'shim')
        os.mkdir(shim_dir)

        source_content = (
            f"ALPHA={secrets.token_hex(6)}\n"
            f"{mask_key}=first-secret\n"
            f" {mask_key}=leading-space-is-not-a-match\n"
            f"{mask_key}_EXTRA=must-remain\n"
            "UNCHANGED=one=two\n"
            f"{mask_key}=second-secret\n"
            "OMEGA=done\n"
        )
        expected = (
            source_content
            .replace(f"{mask_key}=first-secret\n", f"{mask_key}=***\n")
            .replace(f"{mask_key}=second-secret\n", f"{mask_key}=***\n")
        )

        with open(source_path, 'w', newline='') as f:
            f.write(source_content)

        sitecustomize = os.path.join(shim_dir, 'sitecustomize.py')
        with open(sitecustomize, 'w') as f:
            f.write(
                "import fcntl\n"
                "import os\n"
                "_real_flock = fcntl.flock\n"
                "def _checked_flock(fileobj, operation):\n"
                "    fd = fileobj if isinstance(fileobj, int) else fileobj.fileno()\n"
                "    try:\n"
                "        path = os.path.realpath('/proc/self/fd/%d' % fd)\n"
                "    except Exception:\n"
                "        path = '<unknown>'\n"
                "    event = os.environ.get('FLOCK_EVENT_PATH')\n"
                "    if event:\n"
                "        with open(event, 'a') as log:\n"
                "            log.write('%d\\t%s\\n' % (operation, path))\n"
                "            log.flush()\n"
                "    return _real_flock(fileobj, operation)\n"
                "fcntl.flock = _checked_flock\n"
            )

        try:
            with open(RULE_PATH, 'w') as f:
                json.dump({'source': source_path, 'mask_key': mask_key}, f)

            env = os.environ.copy()
            env['PYTHONPATH'] = shim_dir + os.pathsep + env.get('PYTHONPATH', '')
            env['FLOCK_EVENT_PATH'] = event_path

            with open(source_path, 'r') as locked_source:
                fcntl.flock(locked_source, fcntl.LOCK_EX)
                proc = subprocess.Popen(
                    [sys.executable, SCRIPT_PATH],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=env,
                )

                deadline = time.time() + 5
                saw_shared_lock = False
                while time.time() < deadline:
                    if os.path.exists(event_path):
                        with open(event_path, 'r') as log:
                            events = [line.rstrip('\n').split('\t', 1) for line in log]
                        saw_shared_lock = any(
                            int(operation) == fcntl.LOCK_SH
                            and os.path.realpath(path) == os.path.realpath(source_path)
                            for operation, path in events
                        )
                        if saw_shared_lock:
                            break
                    if proc.poll() is not None:
                        break
                    time.sleep(0.05)

                assert saw_shared_lock, "The script did not call fcntl.flock on the rule-selected source with LOCK_SH."
                assert proc.poll() is None, "The script did not block on an exclusive lock held by another process."
                fcntl.flock(locked_source, fcntl.LOCK_UN)

            stdout, stderr = proc.communicate(timeout=10)
            assert proc.returncode == 0, f"The script failed on rule-selected input: {stderr}"
            assert stdout == expected, "The script output was not the exact ordered transformation of the rule-selected source."
        finally:
            if 'proc' in locals() and proc.poll() is None:
                proc.kill()
                proc.communicate()
            with open(RULE_PATH, 'wb') as f:
                f.write(original_rule)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
