#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import datetime
import os
import secrets
import stat
import subprocess
import tempfile
from zoneinfo import ZoneInfo

REPO = "/home/user/monitor.git"
HOOK = REPO + "/hooks/post-receive"
SCRIPT = "/home/user/alert_check.py"
LOG = "/home/user/alerts.log"
ZERO = "0" * 40


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def get_default_interface():
    res = run(["ip", "route"])
    for line in res.stdout.splitlines():
        if line.startswith("default"):
            parts = line.split()
            if "dev" in parts:
                idx = parts.index("dev")
                if idx + 1 < len(parts):
                    return parts[idx + 1]
    return None


def clear_log():
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass


def assert_log(expected):
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    perms = stat.S_IMODE(os.stat(LOG).st_mode)
    assert perms == 0o600, f"Permissions for {LOG} are {oct(perms)}, expected 0o600."
    with open(LOG, "r", encoding="utf-8") as f:
        contents = f.read()
    assert contents.endswith("\n"), "alerts.log must contain complete one-line records"
    actual_lines = contents.splitlines()
    assert collections.Counter(actual_lines) == collections.Counter(expected), \
        f"Expected exactly {expected!r}, found {actual_lines!r}"
    for line in expected:
        assert line in contents, f"Expected log entry {line!r} not found in {LOG}."


def make_commit(work, hour, label):
    day = 1 + secrets.randbelow(27)
    minute = secrets.randbelow(60)
    second = secrets.randbelow(60)
    local_time = datetime.datetime(
        2023 + secrets.randbelow(3), 1 + secrets.randbelow(12), day,
        hour, minute, second, tzinfo=ZoneInfo("Asia/Tokyo")
    )
    timestamp = int(local_time.timestamp())
    env = os.environ.copy()
    env["GIT_AUTHOR_DATE"] = f"@{timestamp} +0000"
    env["GIT_COMMITTER_DATE"] = f"@{timestamp} +0000"
    run(["git", "commit", "--allow-empty", "-m", f"{label}-{secrets.token_hex(8)}"],
        cwd=work, env=env)
    commit = run(["git", "rev-parse", "HEAD"], cwd=work).stdout.strip()
    return commit


def push_records(work, cases, token):
    records = []
    refspecs = []
    for index, hour in enumerate(cases):
        commit = make_commit(work, hour, f"case-{token}-{index}")
        ref = f"refs/heads/verify_{token}_{index}"
        records.append((ZERO, commit, ref, hour))
        refspecs.append(f"{commit}:{ref}")
    run(["git", "push", "origin", *refspecs], cwd=work)
    return records


def expected_alerts(records, iface):
    return [
        f"ALERT: commit={newrev} tz_hour={hour} iface={iface}"
        for _oldrev, newrev, _ref, hour in records
        if hour >= 22 or hour <= 5
    ]


def test_complete_alert_system():
    # Preserve the original artifact checks.
    assert os.path.isfile(HOOK), f"Git hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Git hook at {HOOK} is not executable"
    assert os.path.isfile(SCRIPT), f"Alert script not found at {SCRIPT}"

    iface = get_default_interface()
    assert iface is not None, "Could not determine default network interface."

    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as work:
        run(["git", "init", "-b", "main"], cwd=work)
        run(["git", "config", "user.name", "Verifier User"], cwd=work)
        run(["git", "config", "user.email", "verifier@example.com"], cwd=work)
        run(["git", "remote", "add", "origin", REPO], cwd=work)

        # Exercise an actual multi-ref push at both off-hours boundaries,
        # additional off-hours, and both adjacent normal-hours boundaries.
        clear_log()
        hours = [22, 23, 0, 5, 6, 21, secrets.choice([1, 2, 3, 4]),
                 secrets.choice(list(range(7, 21)))]
        records = push_records(work, hours, token)
        assert_log(expected_alerts(records, iface))

        # Execute the required Python artifact directly with multiple records.
        # This prevents a hook-only implementation from passing.
        clear_log()
        dispatcher_input = "".join(
            f"{oldrev} {newrev} {ref}\n" for oldrev, newrev, ref, _hour in records
        )
        proc = subprocess.run(
            ["python3", SCRIPT], input=dispatcher_input, text=True,
            cwd="/", capture_output=True
        )
        assert proc.returncode == 0, \
            f"alert_check.py failed: stdout={proc.stdout!r} stderr={proc.stderr!r}"
        assert_log(expected_alerts(records, iface))

        # Instrument the mandated path for another push to prove the hook
        # invokes it and forwards every receive record. The wrapper delegates
        # to the submitted script so behavior remains under test.
        saved = f"/home/user/.alert_check_saved_{token}.py"
        marker = f"/home/user/.alert_check_stdin_{token}"
        original_stat = os.stat(SCRIPT)
        with open(SCRIPT, "rb") as f:
            original = f.read()
        with open(saved, "wb") as f:
            f.write(original)
        os.chmod(saved, stat.S_IMODE(original_stat.st_mode))
        wrapper = f'''#!/usr/bin/env python3
import subprocess
import sys
data = sys.stdin.read()
with open({marker!r}, "a", encoding="utf-8") as marker_file:
    marker_file.write(data)
result = subprocess.run([sys.executable, {saved!r}], input=data, text=True)
sys.exit(result.returncode)
'''
        try:
            with open(SCRIPT, "w", encoding="utf-8") as f:
                f.write(wrapper)
            os.chmod(SCRIPT, 0o755)
            clear_log()
            invocation_records = push_records(work, [0, 12, 22], token + "i")
        finally:
            with open(SCRIPT, "wb") as f:
                f.write(original)
            os.chmod(SCRIPT, stat.S_IMODE(original_stat.st_mode))
            os.chown(SCRIPT, original_stat.st_uid, original_stat.st_gid)
            try:
                os.unlink(saved)
            except FileNotFoundError:
                pass

        assert os.path.isfile(marker), "post-receive did not invoke /home/user/alert_check.py"
        with open(marker, "r", encoding="utf-8") as f:
            forwarded = f.read().splitlines()
        os.unlink(marker)
        expected_input = [
            f"{oldrev} {newrev} {ref}"
            for oldrev, newrev, ref, _hour in invocation_records
        ]
        assert collections.Counter(forwarded) == collections.Counter(expected_input), \
            f"Hook did not forward the complete receive input: {forwarded!r}"
        assert_log(expected_alerts(invocation_records, iface))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
