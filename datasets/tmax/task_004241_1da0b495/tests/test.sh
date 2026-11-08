#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tarfile
import uuid


def test_automate_exp_exists():
    path = "/home/user/automate.exp"
    assert os.path.isfile(path), f"Expect script {path} does not exist."


def test_backup_manager_c_exists():
    path = "/home/user/backup_manager.c"
    assert os.path.isfile(path), f"C source file {path} does not exist."


def test_backup_manager_executable():
    path = "/home/user/backup_manager"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), f"File {path} is not executable."


def test_backup_tar_gz_exists_and_contents():
    path = "/home/user/backup.tar.gz"
    assert os.path.isfile(path), f"Backup archive {path} does not exist."

    try:
        with tarfile.open(path, "r:gz") as tar:
            names = tar.getnames()
            # The tar command uses -C $(dirname $src) $(basename $src),
            # so the path inside should start with source_data
            assert any("source_data/data.txt" in name for name in names), f"Archive does not contain 'source_data/data.txt'. Found: {names}"
    except tarfile.ReadError:
        assert False, f"File {path} is not a valid gzip-compressed tar archive."


def test_monitor_log_contents():
    path = "/home/user/monitor.log"
    assert os.path.isfile(path), f"Monitor log {path} does not exist."
    with open(path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, f"Monitor log {path} is empty."
    assert lines[-1] == "BACKUP_SUCCESS\n", f"Monitor log does not end with 'BACKUP_SUCCESS\\n'. Last line was: {repr(lines[-1])}"


def test_fstab_out_contents():
    path = "/home/user/fstab.out"
    assert os.path.isfile(path), f"fstab output file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # UUID=12345678-1234-1234-1234-123456789abc /home/user/backup_drive ext4 defaults,noatime 0 2
    pattern = r"UUID=12345678-1234-1234-1234-123456789abc\s+/home/user/backup_drive\s+ext4\s+defaults,noatime\s+0\s+2"
    assert re.search(pattern, content), f"fstab.out does not contain the correctly formatted mount entry. Content found:\n{content}"


def archive_data():
    with tarfile.open("/home/user/backup.tar.gz", "r:gz") as tar:
        member = next((m for m in tar.getmembers() if m.name.rstrip("/") == "source_data/data.txt"), None)
        assert member is not None, "Generated archive lacks source_data/data.txt"
        extracted = tar.extractfile(member)
        assert extracted is not None
        return extracted.read()


def test_expect_and_c_orchestration_behavior():
    expect_script = "/home/user/automate.exp"
    manager_source = "/home/user/backup_manager.c"
    manager_binary = "/home/user/backup_manager"
    tool = "/home/user/interactive_tool.sh"
    archive = "/home/user/backup.tar.gz"
    monitor = "/home/user/monitor.log"
    response_log = "/tmp/verified_expect_responses"
    rebuilt_manager = "/tmp/verified_backup_manager"

    with open(manager_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backup_manager is not a compiled ELF executable"

    compiled = subprocess.run(
        ["gcc", manager_source, "-o", rebuilt_manager],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"backup_manager.c does not compile:\n{compiled.stderr}"

    # Exercise the Expect program directly against a fresh interactive tool that
    # records all three answers. This prevents a pre-created archive from passing.
    tool_backup = "/tmp/interactive_tool.sh.verifier-backup"
    if os.path.exists(tool_backup):
        os.unlink(tool_backup)
    os.replace(tool, tool_backup)
    challenge = '''#!/bin/bash
echo -n "Enter source directory: "
IFS= read -r src
echo -n "Enter destination archive: "
IFS= read -r dest
echo -n "Confirm backup? (y/n) "
IFS= read -r confirm
printf '%s\\n%s\\n%s\\n' "$src" "$dest" "$confirm" > /tmp/verified_expect_responses
if [ "$src" = /home/user/source_data ] && [ "$dest" = /home/user/backup.tar.gz ] && [ "$confirm" = y ]; then
    tar -czf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
    echo "Backup completed."
    exit 0
fi
exit 9
'''
    try:
        with open(tool, "w") as f:
            f.write(challenge)
        os.chmod(tool, 0o755)
        for path in (archive, response_log):
            if os.path.exists(path):
                os.unlink(path)
        direct = subprocess.run(
            ["/usr/bin/expect", expect_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert direct.returncode == 0, f"Expect automation failed:\n{direct.stdout}\n{direct.stderr}"
        with open(response_log) as f:
            responses = f.read().splitlines()
        assert responses == [
            "/home/user/source_data",
            "/home/user/backup.tar.gz",
            "y",
        ], f"Expect script supplied incorrect answers: {responses!r}"
        assert os.path.isfile(archive), "Expect script did not wait for creation of the archive"
    finally:
        if os.path.exists(tool):
            os.unlink(tool)
        os.replace(tool_backup, tool)

    token = ("verifier-" + uuid.uuid4().hex + "\n").encode()
    with open("/home/user/source_data/data.txt", "wb") as f:
        f.write(token)

    # Interpose on /usr/bin/expect so execution of the submitted binary must be
    # observed invoking the required script, while still running real Expect.
    real_expect = "/tmp/expect.verifier-real"
    invocation_log = "/tmp/verified_expect_invocation"
    if os.path.exists(real_expect):
        os.unlink(real_expect)
    os.replace("/usr/bin/expect", real_expect)
    try:
        wrapper = f'''#!/bin/sh
printf '%s\\n' "$#" > {invocation_log}
for arg in "$@"; do printf '<%s>\\n' "$arg" >> {invocation_log}; done
exec {real_expect} "$@"
'''
        with open("/usr/bin/expect", "w") as f:
            f.write(wrapper)
        os.chmod("/usr/bin/expect", 0o755)

        for path in (archive, monitor, invocation_log):
            if os.path.exists(path):
                os.unlink(path)
        run = subprocess.run(
            [manager_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert os.path.isfile(invocation_log), "backup_manager did not execute /usr/bin/expect"
        with open(invocation_log) as f:
            invocation = f.read().splitlines()
        assert invocation == ["1", "</home/user/automate.exp>"], \
            f"backup_manager invoked Expect with incorrect arguments: {invocation!r}"
        assert os.path.isfile(archive), f"backup_manager did not create the archive (exit {run.returncode})"
        assert archive_data() == token, "backup_manager archive did not contain the fresh source data"
        with open(monitor, "rb") as f:
            assert f.readlines()[-1] == b"BACKUP_SUCCESS\n"

        # Exercise the independently rebuilt C source on the no-archive path.
        # Expect succeeds but deliberately creates nothing, so the C program must
        # inspect the archive and append BACKUP_FAILED.
        with open("/usr/bin/expect", "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod("/usr/bin/expect", 0o755)
        if os.path.exists(archive):
            os.unlink(archive)
        with open(monitor, "wb") as f:
            f.write(b"")
        subprocess.run(
            [rebuilt_manager], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert not os.path.exists(archive), "C program fabricated an archive instead of monitoring Expect"
        with open(monitor, "rb") as f:
            assert f.readlines()[-1] == b"BACKUP_FAILED\n", \
                "Recompiled C program did not log BACKUP_FAILED when no archive existed"
    finally:
        if os.path.exists("/usr/bin/expect"):
            os.unlink("/usr/bin/expect")
        os.replace(real_expect, "/usr/bin/expect")

    # Leave the requested final successful state after the failure-path test.
    final_run = subprocess.run(
        [manager_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert os.path.isfile(archive), f"Final backup run failed (exit {final_run.returncode})"
    assert archive_data() == token
    with open(monitor, "rb") as f:
        assert f.readlines()[-1] == b"BACKUP_SUCCESS\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
