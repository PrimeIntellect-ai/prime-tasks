#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time


def test_phase1_backup_profile():
    profile_path = "/home/user/.backup_profile"
    assert os.path.isfile(profile_path), f"File {profile_path} does not exist."

    with open(profile_path, "r") as f:
        content = f.read()

    expected_exports = [
        "export BACKUP_SOURCE=/home/user/data",
        "export BACKUP_DEST=/home/user/backups/data",
        "export BACKUP_RETENTION_DAYS=14"
    ]

    for exp in expected_exports:
        assert exp in content, f"Missing or incorrect export in {profile_path}: expected '{exp}'"


def test_phase2_custom_fstab():
    fstab_path = "/home/user/custom_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        lines = f.readlines()

    found = False
    for line in lines:
        fields = line.strip().split()
        if len(fields) == 6:
            if fields == ['/home/user/data', '/home/user/backups/data', 'none', 'bind', '0', '0']:
                found = True
                break

    assert found, f"Correct fstab entry not found in {fstab_path}. Expected: '/home/user/data /home/user/backups/data none bind 0 0'"
    assert len(lines) == 1, f"{fstab_path} must contain exactly one line, but contains {len(lines)} lines."


def test_phase3_interactive_automation():
    script_path = "/home/user/auto_provision.py"
    json_path = "/home/user/backup_configured.json"
    utility_path = "/home/user/bin/init_backup.py"

    assert os.path.isfile(json_path), f"File {json_path} does not exist. Did auto_provision.py run successfully?"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    expected_data = {
        "src": "/home/user/data",
        "dst": "/home/user/backups/data",
        "retention": "14"
    }

    assert data == expected_data, f"JSON content in {json_path} does not match expected output. Got {data}"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    audit_dir = tempfile.mkdtemp(prefix="provision_audit_")
    interaction_log = os.path.join(audit_dir, "interaction.json")
    pexpect_log = os.path.join(audit_dir, "pexpect.jsonl")
    sitecustomize_path = os.path.join(audit_dir, "sitecustomize.py")

    with open(sitecustomize_path, "w") as f:
        f.write(r'''import json
import os

log_path = os.environ.get("PEXPECT_AUDIT_LOG")

def record(kind, args, kwargs):
    if log_path:
        with open(log_path, "a") as out:
            out.write(json.dumps({"kind": kind, "args": args, "kwargs": kwargs}, default=str) + "\n")

import pexpect
_original_spawn = pexpect.spawn
def audited_spawn(*args, **kwargs):
    record("spawn", args, kwargs)
    return _original_spawn(*args, **kwargs)
pexpect.spawn = audited_spawn

if hasattr(pexpect, "run"):
    _original_run = pexpect.run
    def audited_run(*args, **kwargs):
        record("run", args, kwargs)
        return _original_run(*args, **kwargs)
    pexpect.run = audited_run

try:
    import pexpect.popen_spawn as _popen_spawn
    _original_popen_spawn = _popen_spawn.PopenSpawn
    def audited_popen_spawn(*args, **kwargs):
        record("PopenSpawn", args, kwargs)
        return _original_popen_spawn(*args, **kwargs)
    _popen_spawn.PopenSpawn = audited_popen_spawn
except Exception:
    pass
''')

    with open(utility_path, "rb") as f:
        original_utility = f.read()
    original_mode = stat.S_IMODE(os.stat(utility_path).st_mode)

    audited_utility = f'''#!/usr/bin/env python3
import json
import time

src = input("Source directory: ").strip()
dst = input("Destination directory: ").strip()
ret = input("Retention days: ").strip()
confirm = input("Proceed with setup? (y/n): ").strip()
time.sleep(1.0)
with open({interaction_log!r}, "w") as f:
    json.dump({{"src": src, "dst": dst, "retention": ret, "confirm": confirm}}, f)
if confirm.lower() != "y":
    print("Aborted.")
    raise SystemExit(1)
with open("/home/user/backup_configured.json", "w") as f:
    json.dump({{"src": src, "dst": dst, "retention": ret}}, f)
print("Configuration successful.")
'''

    try:
        with open(utility_path, "w") as f:
            f.write(audited_utility)
        os.chmod(utility_path, 0o755)
        if os.path.exists(json_path):
            os.unlink(json_path)

        env = os.environ.copy()
        env["PEXPECT_AUDIT_LOG"] = pexpect_log
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = audit_dir if not old_pythonpath else audit_dir + os.pathsep + old_pythonpath

        started = time.monotonic()
        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        elapsed = time.monotonic() - started

        assert result.returncode == 0, (
            f"auto_provision.py failed when executed. stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert elapsed >= 0.8, "auto_provision.py returned before the interactive utility exited."
        assert os.path.isfile(pexpect_log), "auto_provision.py did not invoke the utility through pexpect."

        with open(pexpect_log, "r") as f:
            records = [json.loads(line) for line in f if line.strip()]
        assert records, "No pexpect process invocation was observed."
        assert any(utility_path in json.dumps(record) for record in records), (
            f"pexpect was not used to start {utility_path}. Observed calls: {records}"
        )

        assert os.path.isfile(interaction_log), f"{utility_path} was not run to completion."
        with open(interaction_log, "r") as f:
            interaction = json.load(f)
        assert interaction == {
            "src": "/home/user/data",
            "dst": "/home/user/backups/data",
            "retention": "14",
            "confirm": "y",
        }, f"Incorrect interactive responses: {interaction}"

        assert os.path.isfile(json_path), "The executed automation did not configure the backup utility."
        with open(json_path, "r") as f:
            rerun_data = json.load(f)
        assert rerun_data == expected_data, f"Automation produced incorrect configuration: {rerun_data}"
    finally:
        with open(utility_path, "wb") as f:
            f.write(original_utility)
        os.chmod(utility_path, original_mode)
        shutil.rmtree(audit_dir, ignore_errors=True)


def test_phase4_scheduled_task():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        assert False, "Failed to read crontab. Is it configured?"

    expected_cron = "30 2 * * * /home/user/bin/run_backup.sh"

    found = False
    for line in output.splitlines():
        if " ".join(line.strip().split()) == expected_cron:
            found = True
            break

    assert found, f"Cron entry '{expected_cron}' not found in crontab."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
