#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import glob
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
import time

SCRIPT_PATH = "/home/user/compress_logs.sh"
LOGS_DIR = "/home/user/logs"
FILE_1 = os.path.join(LOGS_DIR, "app1.log")
FILE_2 = os.path.join(LOGS_DIR, "app2.log")
FILE_3 = os.path.join(LOGS_DIR, "app3.log")

EXPECTED_CONTENT_1 = """INFO: Service started
DATA: 10X5Y10Z
ERROR: Disk full warning
DATA: 1005150
INFO: Retrying operation
"""

EXPECTED_CONTENT_2 = """DATA: 50A
INFO: Done
DATA: 1A1B1C
"""

EXPECTED_CONTENT_3 = """INFO: Nothing to see here
ERROR: No data
"""


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_commands():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "flock" in content, "The script must use 'flock' to obtain an exclusive file lock."
    assert "mv" in content, "The script must use 'mv' to atomically replace the original file."


def test_app1_log_compressed():
    assert os.path.isfile(FILE_1), f"File {FILE_1} is missing."
    with open(FILE_1, "r") as f:
        content = f.read()
    assert content == EXPECTED_CONTENT_1, f"Content of {FILE_1} does not match expected compressed state."


def test_app2_log_compressed():
    assert os.path.isfile(FILE_2), f"File {FILE_2} is missing."
    with open(FILE_2, "r") as f:
        content = f.read()
    assert content == EXPECTED_CONTENT_2, f"Content of {FILE_2} does not match expected compressed state."


def test_app3_log_compressed():
    assert os.path.isfile(FILE_3), f"File {FILE_3} is missing."
    with open(FILE_3, "r") as f:
        content = f.read()
    assert content == EXPECTED_CONTENT_3, f"Content of {FILE_3} does not match expected compressed state."


def rle(data):
    if not data:
        return ""
    output = []
    current = data[0]
    count = 1
    for char in data[1:]:
        if char == current:
            count += 1
        else:
            output.append(str(count) + current)
            current = char
            count = 1
    output.append(str(count) + current)
    return "".join(output)


def transform(content):
    output = []
    for line in content.splitlines(keepends=True):
        newline = "\n" if line.endswith("\n") else ""
        body = line[:-1] if newline else line
        if body.startswith("DATA: "):
            body = "DATA: " + rle(body[6:])
        output.append(body + newline)
    return "".join(output)


def run_script(timeout=15):
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )


def test_script_processes_fresh_logs_with_locking_and_atomic_replacement():
    backup_dir = tempfile.mkdtemp(prefix="verifier-log-backup-")
    original_logs = glob.glob(os.path.join(LOGS_DIR, "*.log"))
    try:
        for path in original_logs:
            shutil.move(path, os.path.join(backup_dir, os.path.basename(path)))

        # Verify that processing waits for an exclusive lock held on the actual log.
        lock_data = "DATA: " + (secrets.choice("QWERTY") * 37) + "\nINFO: lock test\n"
        lock_path = os.path.join(LOGS_DIR, "00_" + secrets.token_hex(8) + ".log")
        with open(lock_path, "w") as f:
            f.write(lock_data)
        old_inode = os.stat(lock_path).st_ino

        lock_file = open(lock_path, "r+")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            time.sleep(0.5)
            assert proc.poll() is None, "Script did not wait for the locked log file."
            with open(lock_path, "r") as f:
                assert f.read() == lock_data, "Locked log was modified before its lock was released."
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()

        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, (
            f"Script failed after lock release. stdout={stdout!r}, stderr={stderr!r}"
        )
        with open(lock_path, "r") as f:
            assert f.read() == transform(lock_data)
        assert os.stat(lock_path).st_ino != old_inode, (
            "The log was modified in place rather than replaced via a temporary file."
        )
        os.unlink(lock_path)

        # Fresh randomized names and data prevent hard-coding the setup fixtures.
        token = secrets.token_hex(10)
        repeated = "".join(
            secrets.choice("ABCXYZ0123_-") * secrets.randbelow(45)
            for _ in range(25)
        )
        contents = {
            f"alpha_{token}.log": (
                "INFO: unchanged punctuation !@#$%^&*()\n"
                "DATA: " + repeated + "\n"
                "ERROR: DATA: this is not a data line\n"
                "DATA: 00000000000111112222\n"
            ),
            f"beta_{token}.log": (
                "DATA: ABCDE\n"
                " DATA: AAAAA must remain unchanged\n"
                "DATA:no-space\n"
                "\n"
                "DATA: ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ\n"
            ),
            f"gamma_{token}.log": (
                "INFO: no matching lines here\n"
                "ERROR: preserve this exactly\n"
            ),
        }

        inodes = {}
        expected = {}
        for name, content in contents.items():
            path = os.path.join(LOGS_DIR, name)
            with open(path, "w") as f:
                f.write(content)
            inodes[path] = os.stat(path).st_ino
            expected[path] = transform(content)

        run_script()

        for path, wanted in expected.items():
            assert os.path.isfile(path), f"Script removed {path}."
            with open(path, "r") as f:
                actual = f.read()
            assert actual == wanted, f"Incorrect processing of fresh log {path}: {actual!r}"
            assert os.stat(path).st_ino != inodes[path], (
                f"{path} was not atomically replaced from a temporary file."
            )
    finally:
        for path in glob.glob(os.path.join(LOGS_DIR, "*.log")):
            os.unlink(path)
        for path in glob.glob(os.path.join(backup_dir, "*")):
            shutil.move(path, os.path.join(LOGS_DIR, os.path.basename(path)))
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
