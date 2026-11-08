#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import subprocess
import tarfile
import tempfile
import uuid


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def assert_monitor(executable, expected_code, expected_output, as_user=False):
    cmd = [executable]
    if as_user:
        cmd = ["runuser", "-u", "user", "--", executable]
    result = run(cmd)
    assert result.returncode == expected_code, (
        f"{executable} exited with {result.returncode}, expected {expected_code}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Expected exactly {expected_output!r}, got {result.stdout!r}"
    )


def exercise_monitor(executable):
    state_file = "/home/user/service_data/state.dat"
    token = uuid.uuid4().hex
    saved = None
    saved_mode = None
    if os.path.exists(state_file):
        with open(state_file, "rb") as f:
            saved = f.read()
        saved_mode = os.stat(state_file).st_mode & 0o777

    try:
        with open(state_file, "wb") as f:
            f.write(("READY" + token).encode())
        assert_monitor(executable, 0, "HEALTHY")

        with open(state_file, "wb") as f:
            f.write(("BAD_" + token).encode())
        assert_monitor(executable, 1, "CORRUPT")

        with open(state_file, "wb") as f:
            f.write(b"")
        assert_monitor(executable, 1, "CORRUPT")

        os.unlink(state_file)
        assert_monitor(executable, 1, "CORRUPT")

        with open(state_file, "wb") as f:
            f.write(b"READY")
        os.chmod(state_file, 0)
        assert_monitor(executable, 1, "CORRUPT", as_user=True)
    finally:
        if os.path.exists(state_file):
            os.chmod(state_file, 0o666)
        if saved is None:
            if os.path.exists(state_file):
                os.unlink(state_file)
        else:
            with open(state_file, "wb") as f:
                f.write(saved)
            os.chmod(state_file, saved_mode)


def test_01_setup_script():
    setup_script = "/home/user/setup.sh"
    assert os.path.isfile(setup_script), f"{setup_script} does not exist"
    assert os.access(setup_script, os.X_OK), f"{setup_script} is not executable"

    result = run([setup_script])
    assert result.returncode == 0, f"{setup_script} failed with exit code {result.returncode}"

    state_file = "/home/user/service_data/state.dat"
    assert os.path.isfile(state_file), f"{state_file} was not created"

    with open(state_file, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"Expected state.dat to contain 'READY', but got '{content}'"

    result2 = run([setup_script])
    assert result2.returncode == 0, "Setup script is not idempotent (failed on second run)"


def test_02_monitor():
    monitor_src = "/home/user/monitor.cpp"
    monitor_bin = "/home/user/monitor"
    assert os.path.isfile(monitor_src), f"{monitor_src} does not exist"
    assert os.path.isfile(monitor_bin), f"{monitor_bin} does not exist"
    assert os.access(monitor_bin, os.X_OK), f"{monitor_bin} is not executable"

    with open(monitor_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{monitor_bin} is not a compiled ELF executable"

    result = run([monitor_bin])
    assert result.returncode == 0, f"Monitor exited with {result.returncode}, expected 0"
    assert "HEALTHY" in result.stdout, f"Expected output 'HEALTHY', got '{result.stdout}'"
    assert result.stdout.strip() == "HEALTHY", f"Monitor output was not exactly HEALTHY: {result.stdout!r}"

    fd, compiled = tempfile.mkstemp(prefix="monitor_from_source_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled)
    try:
        build = run(["g++", "-std=c++17", monitor_src, "-o", compiled])
        assert build.returncode == 0, (
            f"{monitor_src} did not compile as C++: {build.stdout}{build.stderr}"
        )
        assert os.path.isfile(compiled) and os.access(compiled, os.X_OK)
        exercise_monitor(monitor_bin)
        exercise_monitor(compiled)
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)


def test_03_backup_script():
    backup_script = "/home/user/backup.sh"
    assert os.path.isfile(backup_script), f"{backup_script} does not exist"
    assert os.access(backup_script, os.X_OK), f"{backup_script} is not executable"

    result = run([backup_script])
    assert result.returncode == 0, f"{backup_script} failed with exit code {result.returncode}"

    backup_archive = "/home/user/backup.tar.gz"
    assert os.path.isfile(backup_archive), f"{backup_archive} was not created"
    assert tarfile.is_tarfile(backup_archive), f"{backup_archive} is not a valid tar archive"
    with tarfile.open(backup_archive, "r:gz") as archive:
        names = [n.lstrip("./") for n in archive.getnames()]
        assert any(n.endswith("home/user/service_data/state.dat") for n in names), (
            "Backup archive does not contain service_data/state.dat"
        )


def test_04_restore_script():
    restore_script = "/home/user/restore.exp"
    restore_tool = "/home/user/restore_tool"
    state_file = "/home/user/service_data/state.dat"
    monitor_bin = "/home/user/monitor"
    backup_script = "/home/user/backup.sh"
    backup_archive = "/home/user/backup.tar.gz"

    assert os.path.isfile(restore_script), f"{restore_script} does not exist"
    assert os.access(restore_script, os.X_OK), f"{restore_script} is not executable"

    with open(restore_script, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!"), "restore.exp must have an Expect shebang"
    shebang = shlex.split(first_line[2:])
    assert shebang, "restore.exp has an invalid shebang"
    is_expect = os.path.basename(shebang[0]) == "expect"
    if os.path.basename(shebang[0]) == "env":
        is_expect = any(os.path.basename(part) == "expect" for part in shebang[1:])
    assert is_expect, "restore.exp must be an Expect script"

    with open(state_file, "w") as f:
        f.write("BROKEN\n")

    result_broken = run([monitor_bin])
    assert result_broken.returncode == 1, "Monitor did not exit with 1 when state was broken"
    assert "CORRUPT" in result_broken.stdout, "Monitor did not output 'CORRUPT' when state was broken"

    result_restore = run([restore_script])
    assert result_restore.returncode == 0, f"{restore_script} failed with exit code {result_restore.returncode}"

    with open(state_file, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"State was not restored properly, got '{content}'"

    result_fixed = run([monitor_bin])
    assert result_fixed.returncode == 0, "Monitor did not exit with 0 after restore"
    assert "HEALTHY" in result_fixed.stdout, "Monitor did not output 'HEALTHY' after restore"

    token = "READY_" + uuid.uuid4().hex
    with open(state_file, "w") as f:
        f.write(token)
    backup_result = run([backup_script])
    assert backup_result.returncode == 0, "Backup script failed for dynamically generated state"

    with tarfile.open(backup_archive, "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.name.lstrip("./").endswith("home/user/service_data/state.dat")]
        assert members, "Dynamic backup omitted state.dat"
        archived = archive.extractfile(members[0]).read().decode()
        assert archived == token, "Backup did not preserve the dynamically generated state"

    with open(state_file, "w") as f:
        f.write("BROKEN_" + uuid.uuid4().hex)

    suffix = uuid.uuid4().hex
    real_tool = f"/tmp/restore_tool_real_{suffix}"
    marker = f"/tmp/restore_tool_called_{suffix}"
    os.replace(restore_tool, real_tool)
    try:
        wrapper = (
            "#!/bin/bash\n"
            f"printf called > {shlex.quote(marker)}\n"
            f"exec {shlex.quote(real_tool)} \"$@\"\n"
        )
        with open(restore_tool, "w") as f:
            f.write(wrapper)
        os.chmod(restore_tool, 0o755)

        dynamic_restore = run([restore_script])
        assert dynamic_restore.returncode == 0, (
            f"restore.exp failed dynamic restore: {dynamic_restore.stdout}{dynamic_restore.stderr}"
        )
        assert os.path.isfile(marker), "restore.exp did not launch /home/user/restore_tool"
        with open(state_file, "r") as f:
            restored = f.read()
        assert restored == token, "restore.exp did not restore the dynamically generated archive contents"
    finally:
        if os.path.exists(restore_tool):
            os.unlink(restore_tool)
        os.replace(real_tool, restore_tool)
        if os.path.exists(marker):
            os.unlink(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
