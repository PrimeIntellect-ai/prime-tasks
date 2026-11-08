#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_monitor.py
import glob
import os
import re
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_symlink_rolled_back():
    symlink_path = "/home/user/app_current"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symlink."
    target = os.readlink(symlink_path)
    expected_target = "/home/user/deployments/v2"
    assert target == expected_target, f"Symlink points to {target}, expected {expected_target} after rollback."


def test_log_rotated_to_archive():
    archive_path = "/home/user/archives/v2_app.log.archive"
    assert os.path.isfile(archive_path), f"Expected archived log file at {archive_path}."

    with open(archive_path, "r") as f:
        content = f.read()
    assert "ERROR: database timeout" in content, f"Archived log {archive_path} does not contain the expected ERROR message."


def test_new_app_log_created_and_empty():
    new_log_path = "/home/user/deployments/v2/app.log"
    assert os.path.isfile(new_log_path), f"Expected new log file at {new_log_path}."

    size = os.path.getsize(new_log_path)
    assert size == 0, f"Expected {new_log_path} to be empty (0 bytes), but got {size} bytes."


def test_other_logs_untouched():
    v1_log = "/home/user/deployments/v1/app.log"
    v3_log = "/home/user/deployments/v3/app.log"

    assert os.path.isfile(v1_log), f"Expected {v1_log} to still exist."
    with open(v1_log, "r") as f:
        assert "Log v1: All good" in f.read(), f"{v1_log} content was unexpectedly altered."

    assert os.path.isfile(v3_log), f"Expected {v3_log} to still exist."
    with open(v3_log, "r") as f:
        assert "Log v3: startup" in f.read(), f"{v3_log} content was unexpectedly altered."


def find_monitor():
    candidates = []
    for path in glob.glob("/home/user/run_monitor*"):
        name = os.path.basename(path)
        if re.fullmatch(r"run_monitor(?:\.[A-Za-z0-9_+-]+)?", name):
            try:
                mode = os.lstat(path).st_mode
            except FileNotFoundError:
                continue
            if stat.S_ISREG(mode):
                candidates.append(path)
    assert candidates, "Expected a regular monitor script named /home/user/run_monitor or /home/user/run_monitor.<extension>."
    preferred = ["/home/user/run_monitor.sh", "/home/user/run_monitor.py", "/home/user/run_monitor.pl", "/home/user/run_monitor"]
    for path in preferred:
        if path in candidates:
            return path
    assert len(candidates) == 1, f"Multiple ambiguous monitor scripts found: {candidates}"
    return candidates[0]


def monitor_command(path):
    if os.access(path, os.X_OK):
        return [path]
    suffixes = {".sh": ["bash"], ".py": ["python3"], ".pl": ["perl"]}
    suffix = Path(path).suffix.lower()
    if suffix in suffixes:
        return suffixes[suffix] + [path]
    with open(path, "rb") as f:
        first = f.readline(4096).decode("utf-8", "replace").strip()
    assert first.startswith("#!"), f"Monitor script {path} is neither executable nor associated with a supported interpreter."
    return shlex.split(first[2:].strip()) + [path]


def write_release(base, name, health, log):
    release = Path(base) / name
    release.mkdir(parents=True)
    (release / "health.txt").write_text(health)
    (release / "app.log").write_text(log)


def run_scenario(script, root, versions, current):
    base = Path(root) / "deployments"
    archive = Path(root) / "archives"
    link = Path(root) / "current_release"
    base.mkdir(parents=True)
    archive.mkdir(parents=True)
    for name, health, log in versions:
        write_release(base, name, health, log)
    (base / "history.txt").write_text("".join(name + "\n" for name, _, _ in versions))
    link.symlink_to(base / current)
    Path("/home/user/monitor.conf").write_text(
        f"DEPLOY_BASE={base}\nCURRENT_LINK={link}\nARCHIVE_DIR={archive}\n"
    )
    result = subprocess.run(
        monitor_command(script), cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, (
        f"Monitor exited with status {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return base, archive, link


def test_monitor_script_behavior_and_configuration_parsing():
    script = find_monitor()
    conf = Path("/home/user/monitor.conf")
    original_conf = conf.read_bytes()
    try:
        with tempfile.TemporaryDirectory(prefix="monitor_verify_") as tmp:
            token = os.path.basename(tmp)

            # A dynamically named degraded release must roll back according to history,
            # then rotate the newly active predecessor's ERROR log.
            root1 = Path(tmp) / "rollback_case"
            versions1 = [
                (f"old_{token}", "OK\n", f"old log {token}\n"),
                (f"good_{token}", "OK\n", f"start {token}\nERROR dynamic-{token}\nend\n"),
                (f"bad_{token}", "DEGRADED\n", f"bad release log {token}\n"),
            ]
            base, archive, link = run_scenario(script, root1, versions1, f"bad_{token}")
            expected_active = base / f"good_{token}"
            assert link.is_symlink()
            assert link.resolve() == expected_active.resolve(), "Rollback did not select the immediately preceding history entry."
            archived = archive / f"good_{token}_app.log.archive"
            assert archived.is_file(), "Active release ERROR log was not moved to the configured archive directory."
            assert archived.read_text() == versions1[1][2], "The rotated archive does not contain the original active log."
            assert (expected_active / "app.log").is_file()
            assert (expected_active / "app.log").stat().st_size == 0, "A new empty active app.log was not created."
            assert (base / f"bad_{token}" / "app.log").read_text() == versions1[2][2]

            # A healthy current release must not roll back, but its own ERROR log must rotate.
            root2 = Path(tmp) / "healthy_case"
            versions2 = [
                (f"prior_{token}", "OK\n", f"prior {token}\n"),
                (f"live_{token}", "OK\n", f"ERROR healthy-{token}\n"),
            ]
            base2, archive2, link2 = run_scenario(script, root2, versions2, f"live_{token}")
            assert link2.resolve() == (base2 / f"live_{token}").resolve(), "Healthy release was incorrectly rolled back."
            assert (archive2 / f"live_{token}_app.log.archive").read_text() == versions2[1][2]
            assert (base2 / f"live_{token}" / "app.log").stat().st_size == 0

            # Only exact DEGRADED health triggers rollback, and logs without uppercase
            # ERROR must remain in place.
            root3 = Path(tmp) / "exactness_case"
            versions3 = [
                (f"before_{token}", "OK\n", f"before {token}\n"),
                (f"current_{token}", "DEGRADED SOON\n", f"lowercase error only {token}\n"),
            ]
            base3, archive3, link3 = run_scenario(script, root3, versions3, f"current_{token}")
            assert link3.resolve() == (base3 / f"current_{token}").resolve(), "Non-exact health content incorrectly triggered rollback."
            assert (base3 / f"current_{token}" / "app.log").read_text() == versions3[1][2]
            assert list(archive3.iterdir()) == [], "A log without the exact uppercase ERROR substring was rotated."
    finally:
        conf.write_bytes(original_conf)
TEST_EOF

python3 -m pytest /tmp/test_monitor.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
