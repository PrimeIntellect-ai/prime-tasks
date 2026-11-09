#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import stat
import subprocess
import tempfile
import uuid

FSTAB = "/home/user/custom_fstab"
SOURCE = "/home/user/monitor.c"
DAEMON = "/home/user/monitor_daemon"
BACKUP_SCRIPT = "/home/user/local_bin/perform_backup.sh"
EXPECTED_LINE = "monitor_fs /home/user/mnt/backup_drive customfs defaults 0 0"


def test_backup_drive_created():
    dir_path = "/home/user/mnt/backup_drive"
    assert os.path.isdir(dir_path), f"Expected directory {dir_path} to exist."


def test_custom_fstab_created():
    assert os.path.isfile(FSTAB), f"Expected file {FSTAB} to exist."
    with open(FSTAB, "r") as f:
        content = f.read()
    assert EXPECTED_LINE in content, f"Expected '{EXPECTED_LINE}' to be in {FSTAB}."


def test_monitor_c_modified():
    assert os.path.isfile(SOURCE), f"Expected C file {SOURCE} to exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "/home/user/custom_fstab" in content, "Expected monitor.c to read from /home/user/custom_fstab."
    assert "/home/user/local_bin/perform_backup.sh" in content, "Expected monitor.c to use the absolute path to perform_backup.sh."


def test_monitor_daemon_compiled():
    assert os.path.isfile(DAEMON), f"Expected compiled binary {DAEMON} to exist."
    assert os.access(DAEMON, os.X_OK), f"Expected binary {DAEMON} to be executable."
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {DAEMON} to be a compiled ELF binary."


def test_backup_executed():
    log_path = "/home/user/mnt/backup_drive/health_status.log"
    assert os.path.isfile(log_path), f"Expected log file {log_path} to exist. Did you run the compiled daemon?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SYSTEM_HEALTHY", f"Expected log file content to be 'SYSTEM_HEALTHY', got '{content}'."


def _exercise(binary, label):
    dest = tempfile.mkdtemp(prefix=f"monitor_{label}_", dir="/tmp")
    marker = os.path.join("/tmp", f"backup_called_{uuid.uuid4().hex}")
    token = uuid.uuid4().hex

    with open(FSTAB, "w") as f:
        f.write(f"monitor_fs {dest} customfs defaults 0 0\n")

    wrapper = f"""#!/bin/bash
set -e
[ \"$#\" -eq 2 ]
[ \"$1\" = {shlex.quote(dest)} ]
[ \"$2\" = SYSTEM_HEALTHY ]
printf '%s' {shlex.quote(token)} > {shlex.quote(marker)}
printf '%s\\n' \"$2\" > \"$1/health_status.log\"
"""
    with open(BACKUP_SCRIPT, "w") as f:
        f.write(wrapper)
    os.chmod(BACKUP_SCRIPT, 0o755)

    result = subprocess.run(
        [binary],
        cwd="/tmp",
        env={"PATH": "/usr/bin:/bin"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{binary} failed under a restricted PATH. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(marker), "The absolute backup script was not invoked with the parsed arguments."
    with open(marker, "r") as f:
        assert f.read() == token
    log_path = os.path.join(dest, "health_status.log")
    assert os.path.isfile(log_path), "The invoked backup script did not create the expected log."
    with open(log_path, "r") as f:
        assert f.read().strip() == "SYSTEM_HEALTHY"


def test_source_parses_fstab_and_invokes_absolute_backup_script():
    with open(FSTAB, "rb") as f:
        original_fstab = f.read()
    with open(BACKUP_SCRIPT, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(BACKUP_SCRIPT).st_mode)

    rebuilt = os.path.join("/tmp", f"monitor_rebuilt_{uuid.uuid4().hex}")
    try:
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"monitor.c did not compile: {compile_result.stderr}"
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"

        _exercise(DAEMON, "submitted")
        _exercise(rebuilt, "rebuilt")
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
        with open(BACKUP_SCRIPT, "wb") as f:
            f.write(original_script)
        os.chmod(BACKUP_SCRIPT, original_mode)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
