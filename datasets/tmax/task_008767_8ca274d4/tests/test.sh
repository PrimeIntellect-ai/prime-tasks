#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time
import zipfile

import pytest


def test_safe_writer_c_exists_and_valid():
    c_file = "/home/user/safe_writer.c"
    assert os.path.isfile(c_file), f"{c_file} is missing"

    with open(c_file, "r") as f:
        content = f.read()

    assert "fcntl" in content, f"{c_file} must use fcntl for locking"
    assert "F_SETLKW" in content, f"{c_file} must use F_SETLKW for exclusive blocking lock"
    assert "struct flock" in content, f"{c_file} must use struct flock"


def test_safe_writer_executable_exists():
    exe_file = "/home/user/safe_writer"
    assert os.path.isfile(exe_file), f"{exe_file} is missing"

    st = os.stat(exe_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"{exe_file} is not executable"
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_file} must be a compiled executable"


def test_extract_sh_exists_and_valid():
    sh_file = "/home/user/extract.sh"
    assert os.path.isfile(sh_file), f"{sh_file} is missing"

    st = os.stat(sh_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"{sh_file} is not executable"

    with open(sh_file, "r") as f:
        content = f.read()

    assert "&" in content, f"{sh_file} must run processes in the background using '&'"
    assert "wait" in content, f"{sh_file} must wait for background processes using 'wait'"
    assert "safe_writer" in content, f"{sh_file} must pipe to safe_writer"


def test_disk_alerts_log():
    log_file = "/home/user/disk_alerts.log"
    assert os.path.isfile(log_file), f"{log_file} is missing"

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "[DISK_FULL] Device /dev/sda1 is out of space",
        "[DISK_FULL] Write failed on /var/log",
        "[DISK_FULL] Quota exceeded for user backup",
        "[DISK_FULL] Cannot create temporary file"
    ]

    assert len(lines) == 4, f"{log_file} should contain exactly 4 lines, found {len(lines)}"

    for expected in expected_lines:
        assert expected in lines, f"Missing expected line in {log_file}: '{expected}'"


def compile_source():
    built = "/tmp/safe_writer_from_source"
    result = subprocess.run(
        ["gcc", "/home/user/safe_writer.c", "-o", built],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"safe_writer.c does not compile with gcc:\n{result.stderr}"
    return built


def exercise_writer(executable):
    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "alerts.log")
        with open(output, "w") as f:
            f.write("already present\n")

        supplied = (
            "ordinary line\n"
            "prefix [DISK_FULL] suffix\n"
            "[disk_full] wrong case\n"
            "[DISK_FULL missing bracket\n"
            "second [DISK_FULL] dynamically generated value 91473\n"
        )
        result = subprocess.run(
            [executable, output],
            input=supplied,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, f"writer failed: {result.stderr}"
        with open(output) as f:
            assert f.read().splitlines() == [
                "already present",
                "prefix [DISK_FULL] suffix",
                "second [DISK_FULL] dynamically generated value 91473",
            ]

        no_arg = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        two_args = subprocess.run(
            [executable, output, output], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        assert no_arg.returncode != 0, "safe_writer must reject zero arguments"
        assert two_args.returncode != 0, "safe_writer must reject more than one argument"


def assert_blocking_posix_lock(executable):
    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "locked.log")
        with open(output, "w") as f:
            f.write("seed\n")

        with open(output, "r+b", buffering=0) as held:
            held.seek(0)
            fcntl.lockf(held, fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [executable, output],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            proc.stdin.write(b"[DISK_FULL] lock probe 58129\n")
            proc.stdin.flush()
            proc.stdin.close()

            waiter_seen = False
            deadline = time.time() + 3
            while time.time() < deadline and proc.poll() is None:
                try:
                    with open("/proc/locks") as locks:
                        entries = locks.read().splitlines()
                    waiter_seen = any(
                        "->" in entry and re.search(rf"\b{proc.pid}\b", entry)
                        for entry in entries
                    )
                except OSError:
                    waiter_seen = False
                if waiter_seen:
                    break
                time.sleep(0.05)

            assert proc.poll() is None, "safe_writer wrote without waiting for the held lock"
            assert waiter_seen, "safe_writer did not issue a blocking POSIX record-lock request"
            with open(output) as f:
                assert f.read() == "seed\n", "safe_writer modified the file before acquiring its lock"

            fcntl.lockf(held, fcntl.LOCK_UN)
            proc.wait(timeout=5)
            stderr = proc.stderr.read().decode(errors="replace")
            assert proc.returncode == 0, f"safe_writer failed after lock release: {stderr}"

        with open(output) as f:
            assert f.read().splitlines() == ["seed", "[DISK_FULL] lock probe 58129"]


def test_safe_writer_runtime_behavior_and_locking():
    submitted = "/home/user/safe_writer"
    rebuilt = compile_source()
    for executable in (submitted, rebuilt):
        exercise_writer(executable)
        assert_blocking_posix_lock(executable)


def make_archive(path, member_name, text):
    with tempfile.TemporaryDirectory() as td:
        zip_path = os.path.join(td, "logs.zip")
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(member_name, text)
        with tarfile.open(path, "w") as tf:
            tf.add(zip_path, arcname="logs.zip")


def test_extract_script_dynamic_archives_concurrency_and_wait():
    archives = "/home/user/archives"
    backup = f"/tmp/archives-verifier-backup-{os.getpid()}"
    writer = "/home/user/safe_writer"
    real_writer = f"/tmp/safe-writer-verifier-real-{os.getpid()}"
    output = "/home/user/disk_alerts.log"
    trace = f"/tmp/safe-writer-trace-{os.getpid()}"

    output_existed = os.path.exists(output)
    output_backup = None
    if output_existed:
        with open(output, "rb") as f:
            output_backup = f.read()

    os.rename(archives, backup)
    os.mkdir(archives)
    os.rename(writer, real_writer)
    wrapper = f'''#!/bin/bash
printf 'START %s %s\\n' "$$" "$(date +%s%N)" >> {trace}
sleep 1.5
"{real_writer}" "$@"
rc=$?
printf 'DONE %s %s\\n' "$$" "$(date +%s%N)" >> {trace}
exit $rc
'''
    with open(writer, "w") as f:
        f.write(wrapper)
    os.chmod(writer, 0o755)

    expected = [
        "node-a [DISK_FULL] dynamic alert 301",
        "[DISK_FULL] dynamic alert 302",
        "node-b [DISK_FULL] dynamic alert 401",
        "[DISK_FULL] dynamic alert 402",
        "node-c [DISK_FULL] dynamic alert 501",
        "[DISK_FULL] dynamic alert 502",
    ]

    try:
        make_archive(
            os.path.join(archives, "dynamic-a.tar"),
            "a.txt",
            "ignore a\n" + expected[0] + "\n" + expected[1] + "\nnot an alert\n",
        )
        make_archive(
            os.path.join(archives, "dynamic-b.tar"),
            "b.txt",
            expected[2] + "\nnoise [disk_full]\n" + expected[3] + "\n",
        )
        make_archive(
            os.path.join(archives, "dynamic-c.tar"),
            "c.txt",
            "startup\n" + expected[4] + "\n" + expected[5] + "\nshutdown\n",
        )
        if os.path.exists(output):
            os.unlink(output)
        if os.path.exists(trace):
            os.unlink(trace)

        result = subprocess.run(
            ["/home/user/extract.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"extract.sh failed:\n{result.stderr}"
        assert os.path.isfile(output), "extract.sh did not create disk_alerts.log"
        with open(output) as f:
            actual = [line.rstrip("\n") for line in f if line.rstrip("\n")]
        assert sorted(actual) == sorted(expected), "extract.sh did not extract and filter the dynamic archives correctly"

        assert os.path.isfile(trace), "extract.sh did not invoke /home/user/safe_writer"
        with open(trace) as f:
            records = [line.split() for line in f if line.strip()]
        starts = [int(parts[2]) for parts in records if parts[0] == "START"]
        dones = [parts for parts in records if parts[0] == "DONE"]
        assert len(starts) == 3, f"expected one safe_writer invocation per archive, got {len(starts)}"
        assert len(dones) == 3, "extract.sh exited before all safe_writer processes completed"
        assert max(starts) - min(starts) < 1_000_000_000, "archive pipelines were not launched concurrently"
    finally:
        if os.path.exists(writer):
            os.unlink(writer)
        if os.path.exists(real_writer):
            os.rename(real_writer, writer)
        shutil.rmtree(archives, ignore_errors=True)
        if os.path.exists(backup):
            os.rename(backup, archives)
        if output_existed:
            with open(output, "wb") as f:
                f.write(output_backup)
        elif os.path.exists(output):
            os.unlink(output)
        if os.path.exists(trace):
            os.unlink(trace)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
