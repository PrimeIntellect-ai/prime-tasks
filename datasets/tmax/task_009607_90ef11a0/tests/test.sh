#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import tempfile

EXECUTABLE_PATH = "/home/user/app/monitor"
SOURCE_PATH = "/home/user/src/monitor.c"
LOG_PATH = "/home/user/app/health.log"
ARCHIVE_PATH = "/home/user/backup/health_backup.tar.gz"


def _remove_outputs(workdir):
    for path in (
        LOG_PATH,
        ARCHIVE_PATH,
        os.path.join(workdir, "health.log"),
        os.path.join(workdir, "health_backup.tar.gz"),
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def _run_case(executable, pid, expected_status, workdir):
    _remove_outputs(workdir)
    result = subprocess.run(
        [executable, str(pid)],
        cwd=workdir,
        env={},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        text=True,
    )
    assert result.returncode == 0, (
        f"{executable} failed in an empty environment: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.isfile(LOG_PATH), f"{executable} did not create {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        log_content = f.read()
    assert f"STATUS: {expected_status}" in log_content, (
        f"Expected STATUS: {expected_status} for PID {pid}, got {log_content!r}"
    )

    assert os.path.isfile(ARCHIVE_PATH), f"{executable} did not create {ARCHIVE_PATH}"
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"{ARCHIVE_PATH} is not a valid tar archive"
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == "health.log"]
        assert members, "The generated archive does not contain health.log"
        archived = tar.extractfile(members[0])
        assert archived is not None
        assert archived.read() == log_content.encode(), "Archived health.log does not match the generated log"

    assert not os.path.exists(os.path.join(workdir, "health.log")), "Monitor wrote a relative health.log"
    assert not os.path.exists(os.path.join(workdir, "health_backup.tar.gz")), "Monitor wrote a relative backup archive"


def _exercise_monitor(executable):
    with tempfile.TemporaryDirectory(prefix="monitor-cwd-") as workdir:
        dead = subprocess.Popen(["/bin/true"], env={})
        dead.wait(timeout=5)
        _run_case(executable, dead.pid, "DOWN", workdir)

        live = subprocess.Popen(["/bin/sleep", "3600"], env={})
        try:
            _run_case(executable, live.pid, "OK", workdir)
        finally:
            live.terminate()
            try:
                live.wait(timeout=5)
            except subprocess.TimeoutExpired:
                live.kill()
                live.wait(timeout=5)


def test_deployment_works_from_empty_environment():
    """Execute both the submitted artifact and a fresh build of the submitted source."""
    assert os.path.isfile(SOURCE_PATH), f"Source code file {SOURCE_PATH} is missing."
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} does not exist."

    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted monitor is not a compiled ELF executable."

    with tempfile.TemporaryDirectory(prefix="monitor-build-") as builddir:
        rebuilt = os.path.join(builddir, "monitor")
        compile_result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            text=True,
        )
        assert compile_result.returncode == 0, (
            f"monitor.c does not compile: stdout={compile_result.stdout!r}, "
            f"stderr={compile_result.stderr!r}"
        )
        _exercise_monitor(rebuilt)

    _exercise_monitor(EXECUTABLE_PATH)


def test_monitor_compiled_and_executable():
    """Verify that the compiled monitor executable exists and is executable."""
    executable_path = "/home/user/app/monitor"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    st = os.stat(executable_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Executable {executable_path} is not executable."


def test_health_log_created_and_contains_status():
    """Verify that the health.log is created in the correct location and contains a status."""
    log_path = "/home/user/app/health.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    assert "STATUS:" in content, f"Log file {log_path} does not contain the expected 'STATUS:' string."


def test_backup_archive_created_and_valid():
    """Verify that the backup archive is created in the correct location and is a valid tarball."""
    archive_path = "/home/user/backup/health_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Backup archive {archive_path} does not exist."

    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("health.log" in name for name in names), "The backup archive does not contain 'health.log'."


def test_monitor_c_uses_absolute_paths():
    """Verify that monitor.c has been updated to use absolute paths."""
    src_file = "/home/user/src/monitor.c"
    assert os.path.isfile(src_file), f"Source code file {src_file} is missing."

    with open(src_file, "r") as f:
        content = f.read()

    assert "/home/user/app/health.log" in content, "The absolute path '/home/user/app/health.log' was not found in monitor.c"
    assert "/home/user/backup/health_backup.tar.gz" in content, "The absolute path '/home/user/backup/health_backup.tar.gz' was not found in monitor.c"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
