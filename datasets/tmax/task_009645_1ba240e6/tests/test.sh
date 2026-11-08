#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import stat
import subprocess
import tempfile


def test_directories_and_files_exist():
    assert os.path.isdir("/home/user/backups"), "Directory /home/user/backups does not exist."
    assert os.path.isfile("/home/user/monitor.py"), "/home/user/monitor.py does not exist."
    assert os.path.isfile("/home/user/start_service.sh"), "/home/user/start_service.sh does not exist."


def test_wrapper_is_executable():
    st = os.stat("/home/user/start_service.sh")
    assert bool(st.st_mode & stat.S_IXUSR), "/home/user/start_service.sh is not executable."


def test_monitor_no_backup_dir_env():
    env = os.environ.copy()
    env.pop("BACKUP_DIR", None)

    result = subprocess.run(
        ["python3", "/home/user/monitor.py"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 2, f"Expected exit code 2 when BACKUP_DIR is not set, got {result.returncode}."


def test_monitor_nonexistent_backup_dir():
    env = os.environ.copy()
    env["BACKUP_DIR"] = "/tmp/verifier-directory-that-does-not-exist"
    result = subprocess.run(
        ["python3", "/home/user/monitor.py"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 2, f"Expected exit code 2 for a nonexistent BACKUP_DIR, got {result.returncode}."


def test_monitor_uses_backup_dir_environment_variable():
    with tempfile.TemporaryDirectory(prefix="monitor-target-") as target:
        env = os.environ.copy()
        env["BACKUP_DIR"] = target

        result = subprocess.run(
            ["python3", "/home/user/monitor.py"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 1, f"Expected exit code 1 for an empty BACKUP_DIR, got {result.returncode}."
        assert result.stdout == "", f"Expected no stdout for a missing backup, got {result.stdout!r}."
        assert result.stderr == "CRITICAL: Backup missing\n", f"Unexpected stderr: {result.stderr!r}."

        with open(os.path.join(target, "independent.bak"), "w") as f:
            f.write("dummy")

        result = subprocess.run(
            ["python3", "/home/user/monitor.py"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"Expected exit code 0 when BACKUP_DIR contains a backup, got {result.returncode}."
        assert result.stdout == "OK: Backup present\n", f"Unexpected stdout: {result.stdout!r}."
        assert result.stderr == "", f"Expected no stderr when a backup exists, got {result.stderr!r}."


def test_wrapper_no_backups():
    for f in glob.glob("/home/user/backups/*.bak"):
        if os.path.isfile(f) or os.path.islink(f):
            os.remove(f)

    if os.path.exists("/home/user/monitor.err"):
        os.remove("/home/user/monitor.err")
    if os.path.exists("/home/user/monitor.log"):
        os.remove("/home/user/monitor.log")

    result = subprocess.run(["/home/user/start_service.sh"])
    assert result.returncode == 1, f"Expected exit code 1 when no backups exist, got {result.returncode}."

    assert os.path.isfile("/home/user/monitor.err"), "/home/user/monitor.err was not created."
    with open("/home/user/monitor.err", "r") as f:
        err_content = f.read()

    assert "CRITICAL: Backup missing" in err_content, "monitor.err does not contain the expected CRITICAL message."
    assert err_content == "CRITICAL: Backup missing\n", f"Unexpected monitor.err content: {err_content!r}."
    with open("/home/user/monitor.log", "r") as f:
        assert f.read() == "", "monitor.log should be empty when no backup exists."


def test_wrapper_with_backups():
    test_bak = "/home/user/backups/test.bak"
    with open(test_bak, "w") as f:
        f.write("dummy")

    try:
        result = subprocess.run(["/home/user/start_service.sh"])
        assert result.returncode == 0, f"Expected exit code 0 when backup exists, got {result.returncode}."

        assert os.path.isfile("/home/user/monitor.log"), "/home/user/monitor.log was not created."
        with open("/home/user/monitor.log", "r") as f:
            lines = f.readlines()

        assert len(lines) > 0, "/home/user/monitor.log is empty."
        assert "OK: Backup present" in lines[-1], "The last line of monitor.log does not contain the expected OK message."
        assert "".join(lines) == "OK: Backup present\n", f"Unexpected monitor.log content: {''.join(lines)!r}."
        with open("/home/user/monitor.err", "r") as f:
            assert f.read() == "", "monitor.err should be empty when a backup exists."
    finally:
        if os.path.exists(test_bak):
            os.remove(test_bak)


def test_wrapper_exports_env_executes_monitor_redirects_and_propagates_status():
    monitor_path = "/home/user/monitor.py"
    marker_path = "/tmp/monitor-wrapper-probe"
    with open(monitor_path, "rb") as f:
        original_monitor = f.read()
    original_mode = stat.S_IMODE(os.stat(monitor_path).st_mode)

    probe = b'''#!/usr/bin/python3
import os
import sys
with open("/tmp/monitor-wrapper-probe", "w") as f:
    f.write(os.environ.get("BACKUP_DIR", "<unset>"))
print("PROBE STDOUT")
print("PROBE STDERR", file=sys.stderr)
sys.exit(7)
'''

    try:
        if os.path.exists(marker_path):
            os.remove(marker_path)
        with open(monitor_path, "wb") as f:
            f.write(probe)
        os.chmod(monitor_path, 0o755)

        env = os.environ.copy()
        env["BACKUP_DIR"] = "/tmp/caller-supplied-wrong-directory"
        result = subprocess.run(
            ["/home/user/start_service.sh"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        assert result.returncode == 7, f"Wrapper did not propagate monitor.py's exit code 7; got {result.returncode}."
        assert os.path.isfile(marker_path), "Wrapper did not execute /home/user/monitor.py."
        with open(marker_path, "r") as f:
            assert f.read() == "/home/user/backups", "Wrapper did not export BACKUP_DIR=/home/user/backups to monitor.py."
        assert result.stdout == "", "Monitor stdout leaked through the wrapper instead of being redirected."
        assert result.stderr == "", "Monitor stderr leaked through the wrapper instead of being redirected."
        with open("/home/user/monitor.log", "r") as f:
            assert f.read() == "PROBE STDOUT\n", "Wrapper did not redirect monitor.py stdout to monitor.log."
        with open("/home/user/monitor.err", "r") as f:
            assert f.read() == "PROBE STDERR\n", "Wrapper did not redirect monitor.py stderr to monitor.err."
    finally:
        with open(monitor_path, "wb") as f:
            f.write(original_monitor)
        os.chmod(monitor_path, original_mode)
        if os.path.exists(marker_path):
            os.remove(marker_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
