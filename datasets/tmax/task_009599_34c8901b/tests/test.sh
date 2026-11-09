#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import stat
import subprocess
import tempfile
import uuid


def test_c_code_modified():
    c_file_path = "/home/user/src/restore_monitor.c"
    assert os.path.isfile(c_file_path), f"C source file {c_file_path} is missing"

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "getenv" in content, "getenv is not used in the modified C source file"
    assert "MONITOR_SOCK" in content, "The environment variable MONITOR_SOCK is not referenced in the C code"
    assert "/var/run/restore.sock" not in content, "The hardcoded socket path was not removed from the C code"


def assert_monitor_behavior(program):
    unset_env = os.environ.copy()
    unset_env.pop("MONITOR_SOCK", None)
    result = subprocess.run(
        [program], env=unset_env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert result.returncode == 1, "Monitor must exit with code 1 when MONITOR_SOCK is unset"

    for _ in range(2):
        socket_path = os.path.join(tempfile.gettempdir(), f"monitor-{uuid.uuid4().hex}.sock")
        env = os.environ.copy()
        env["MONITOR_SOCK"] = socket_path
        try:
            result = subprocess.run(
                [program], env=env, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=5
            )
            assert result.returncode == 0, (
                f"Monitor failed with MONITOR_SOCK={socket_path}: {result.stderr}"
            )
            assert os.path.exists(socket_path), "Monitor did not bind at the path from MONITOR_SOCK"
            assert stat.S_ISSOCK(os.stat(socket_path).st_mode), (
                "Path created from MONITOR_SOCK is not a Unix-domain socket"
            )
        finally:
            if os.path.lexists(socket_path):
                os.unlink(socket_path)


def test_modified_source_compiles_and_uses_environment():
    source = "/home/user/src/restore_monitor.c"
    with tempfile.TemporaryDirectory() as temp_dir:
        compiled = os.path.join(temp_dir, "restore_monitor_from_source")
        result = subprocess.run(
            ["gcc", source, "-o", compiled],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"Modified C source does not compile with gcc: {result.stderr}"
        assert_monitor_behavior(compiled)


def test_executable_compiled():
    bin_path = "/home/user/bin/restore_monitor"
    assert os.path.isfile(bin_path), f"Executable {bin_path} is missing"
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable"

    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled ELF executable"

    assert_monitor_behavior(bin_path)


def test_bash_profile_updated():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"Profile file {profile_path} is missing"

    with open(profile_path, "r") as f:
        content = f.read()

    # Look for export MONITOR_SOCK=/home/user/run/monitor.sock
    match = re.search(r"export\s+MONITOR_SOCK\s*=\s*['\"]?/home/user/run/monitor\.sock['\"]?", content)
    assert match is not None, "MONITOR_SOCK export is missing or incorrect in .bash_profile"


def test_cron_backup_file():
    cron_backup_path = "/home/user/cron_backup.txt"
    assert os.path.isfile(cron_backup_path), f"Cron backup file {cron_backup_path} is missing"

    with open(cron_backup_path, "r") as f:
        content = f.read()

    assert "*/5 * * * * /home/user/bin/restore_monitor" in content, "Cron backup file does not contain the correct cron job"


def test_actual_crontab():
    try:
        output = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        output = ""

    assert "*/5 * * * * /home/user/bin/restore_monitor" in output, "The cron job is not actually scheduled in crontab"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
