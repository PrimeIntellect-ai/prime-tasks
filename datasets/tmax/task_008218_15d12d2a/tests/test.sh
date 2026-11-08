#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import gzip

def test_script_exists_and_executable():
    script_path = "/home/user/archive_errors.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable by the owner."

def test_script_uses_flock():
    script_path = "/home/user/archive_errors.sh"
    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "flock -s" in content or "flock --shared" in content, \
        "Script does not use 'flock -s' or 'flock --shared' as required to acquire a shared lock."

def test_archive_exists():
    archive_path = "/home/user/archive/recent_errors.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

def test_archive_contents():
    archive_path = "/home/user/archive/recent_errors.gz"
    assert os.path.isfile(archive_path), f"Cannot verify contents, {archive_path} is missing."

    expected_content = """[ERROR]
Database connection timeout
Retry count: 3
[END ERROR]
[ERROR]
NullPointerException
at com.example.Main.main(Main.java:15)
[END ERROR]
[ERROR]
Disk space low
Volume: /dev/sda1
[END ERROR]"""

    try:
        with gzip.open(archive_path, "rt", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        assert False, f"Failed to read {archive_path} as a gzip file: {e}"

    assert content.strip() == expected_content.strip(), \
        "The extracted error blocks in the gzip file do not match the expected output or are not in alphabetical order."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_behavior.py
import fcntl
import gzip
import os
import secrets
import subprocess
import time

SCRIPT = "/home/user/archive_errors.sh"
LOG_DIR = "/home/user/app_logs"
ARCHIVE = "/home/user/archive/recent_errors.gz"


def read_archive():
    assert os.path.isfile(ARCHIVE), "The script did not create the requested archive"
    with gzip.open(ARCHIVE, "rt", encoding="utf-8") as f:
        return f.read()


def run_script(timeout=8):
    result = subprocess.run([SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=timeout)
    assert result.returncode == 0, \
        f"Script failed with status {result.returncode}: {result.stderr}"


def test_changed_inputs_order_filtering_parsing_and_real_locking():
    for root, dirs, files in os.walk(LOG_DIR, topdown=False):
        for name in files:
            os.unlink(os.path.join(root, name))
        for name in dirs:
            os.rmdir(os.path.join(root, name))

    token = secrets.token_hex(8)
    first = os.path.join(LOG_DIR, f"00_{token}.log")
    second = os.path.join(LOG_DIR, f"99_{token}.log")
    old = os.path.join(LOG_DIR, f"50_old_{token}.log")
    nonlog = os.path.join(LOG_DIR, f"10_{token}.txt")

    block_a = f"[ERROR]\nalpha-{token}\ntrace-a\n[END ERROR]\n"
    block_b = f"[ERROR]\nbeta-{token}\n[END ERROR]\n"
    block_c = f"[ERROR]\ngamma-{token}\ntrace-c\n[END ERROR]\n"
    block_d = f"[ERROR]\nchanged-{token}\n[END ERROR]\n"

    # Create in reverse lexical order so output must follow path sorting, not creation order.
    with open(second, "w", encoding="utf-8") as f:
        f.write("ordinary line\n" + block_b + "[ERROR] not-a-delimiter\n" + block_c)
    with open(first, "w", encoding="utf-8") as f:
        f.write("prefix [ERROR]\nignored\n[END ERROR] suffix\n" + block_a + "tail\n")
    with open(old, "w", encoding="utf-8") as f:
        f.write(f"[ERROR]\nold-{token}\n[END ERROR]\n")
    with open(nonlog, "w", encoding="utf-8") as f:
        f.write(f"[ERROR]\nnonlog-{token}\n[END ERROR]\n")

    old_time = time.time() - 5 * 24 * 60 * 60
    os.utime(old, (old_time, old_time))

    expected = block_a + block_b + block_c
    run_script()
    assert read_archive() == expected, \
        "Rerunning on fresh logs did not correctly filter, sort, and extract exact error blocks"

    # Change an input and require another execution to regenerate, rather than reuse fixed output.
    with open(second, "a", encoding="utf-8") as f:
        f.write(block_d)
    expected += block_d
    run_script()
    assert read_archive() == expected, "The archive was not regenerated after a log changed"

    # An exclusive writer lock on the first file must prevent the script from reading it.
    with open(first, "r", encoding="utf-8") as locked:
        fcntl.flock(locked.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen([SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            time.sleep(0.75)
            assert proc.poll() is None, \
                "The script did not wait for an exclusive lock on a log file"
        finally:
            fcntl.flock(locked.fileno(), fcntl.LOCK_UN)
        stdout, stderr = proc.communicate(timeout=8)
        assert proc.returncode == 0, f"Script failed after the lock was released: {stderr}"
    assert read_archive() == expected

    # A genuine shared lock must remain compatible with another shared reader.
    with open(first, "r", encoding="utf-8") as locked:
        fcntl.flock(locked.fileno(), fcntl.LOCK_SH)
        run_script(timeout=4)
        fcntl.flock(locked.fileno(), fcntl.LOCK_UN)
    assert read_archive() == expected
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 -m pytest /tmp/test_dynamic_behavior.py -x --tb=short 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
