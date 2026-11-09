#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import fcntl
import glob
import os
import secrets
import signal
import stat
import struct
import subprocess
import time

REPORTS_DIR = "/home/user/reports"
MASTER_LOG = "/home/user/master_log.txt"
LOCK_FILE = "/home/user/master_log.lock"
TOTAL_USAGE = "/home/user/total_usage.txt"
SCRIPT_PATH = "/home/user/aggregator.sh"


def test_no_bin_files():
    """Verify that all .bin files have been deleted from the reports directory."""
    bin_files = glob.glob(os.path.join(REPORTS_DIR, "*.bin"))
    assert len(bin_files) == 0, f"Found binary files that should have been deleted: {bin_files}"


def test_master_log_content():
    """Verify that the master log contains the extracted data in the correct format."""
    assert os.path.isfile(MASTER_LOG), f"{MASTER_LOG} does not exist."

    with open(MASTER_LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {"ALPHA:1024", "BETA:2048", "GAMMA:512"}
    actual_lines = set(lines)

    missing = expected_lines - actual_lines
    assert not missing, f"master_log.txt is missing expected entries: {missing}"

    # We only check that the expected lines are present.
    for exp in expected_lines:
        assert exp in actual_lines, f"Expected '{exp}' in {MASTER_LOG}"


def test_total_usage_content():
    """Verify that the total usage file contains the correct sum."""
    assert os.path.isfile(TOTAL_USAGE), f"{TOTAL_USAGE} does not exist."

    with open(TOTAL_USAGE, "r") as f:
        content = f.read().strip()

    assert content == "3584", f"Expected total usage to be '3584', but got '{content}'"


def test_script_requirements():
    """Verify that the script exists, is executable, and contains required commands."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "flock" in content, "The script does not contain 'flock' for concurrent-safe aggregation."
    assert "mv" in content, "The script does not contain 'mv' for atomic summary update."


def test_script_runtime_behavior():
    """Execute the script on fresh, unpredictable mixed-encoding reports."""
    token = secrets.token_hex(5).upper()
    usages = [
        1000 + secrets.randbelow(7000),
        1000 + secrets.randbelow(7000),
        1000 + secrets.randbelow(7000),
    ]
    names = [f"ALPHA_{token}", f"BÉTA_{token}", f"GAMMA_雪_{token}"]
    encodings = ["utf-16le", "iso-8859-1", "utf-8"]

    for pattern in ("*.dat", "*.bin"):
        for path in glob.glob(os.path.join(REPORTS_DIR, pattern)):
            os.unlink(path)

    for i, (name, usage, encoding) in enumerate(zip(names, usages, encodings)):
        payload = f"VOLUME:{name}|USAGE:{usage}".encode(encoding)
        with open(os.path.join(REPORTS_DIR, f"runtime_{i}.dat"), "wb") as f:
            f.write(payload)

    for i in range(2):
        with open(os.path.join(REPORTS_DIR, f"runtime_garbage_{i}.bin"), "wb") as f:
            f.write(os.urandom(4096 + i))

    for path in (MASTER_LOG, TOTAL_USAGE, LOCK_FILE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # A direct write through this symlink would alter the sentinel. A proper
    # temporary-file-and-mv update replaces the symlink atomically instead.
    sentinel = f"/tmp/aggregator_sentinel_{token}"
    with open(sentinel, "w") as f:
        f.write("UNCHANGED")
    os.chmod(sentinel, 0o666)
    os.symlink(sentinel, TOTAL_USAGE)

    # Watch for a rename/move into total_usage.txt, proving the update was
    # installed atomically rather than merely written in place.
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    inotify_fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert inotify_fd >= 0, "Unable to initialize inotify"
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(inotify_fd, b"/home/user", IN_MOVED_TO)
    assert wd >= 0, "Unable to watch /home/user for atomic replacement"

    lock_fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o666)
    os.chmod(LOCK_FILE, 0o666)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)

    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    time.sleep(1.5)
    was_blocked = proc.poll() is None
    log_untouched = not os.path.exists(MASTER_LOG) or os.path.getsize(MASTER_LOG) == 0

    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)

    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        raise AssertionError(f"aggregator.sh timed out; stdout={stdout!r}, stderr={stderr!r}")

    assert was_blocked, "aggregator.sh did not wait for the exclusive master_log.lock lock"
    assert log_untouched, "master_log.txt was written while another process held master_log.lock"
    assert proc.returncode == 0, (
        f"aggregator.sh exited with {proc.returncode}; stdout={stdout!r}, stderr={stderr!r}"
    )

    assert not glob.glob(os.path.join(REPORTS_DIR, "*.bin")), "Runtime .bin files were not deleted"

    assert os.path.isfile(MASTER_LOG), "Runtime execution did not create master_log.txt"
    with open(MASTER_LOG, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [f"{name}:{usage}" for name, usage in zip(names, usages)]
    assert sorted(actual_lines) == sorted(expected_lines), (
        f"Expected exactly {expected_lines!r}, got {actual_lines!r}"
    )

    assert os.path.isfile(TOTAL_USAGE), "Runtime execution did not create total_usage.txt"
    assert not os.path.islink(TOTAL_USAGE), "total_usage.txt symlink was not atomically replaced"
    with open(TOTAL_USAGE, "r", encoding="utf-8") as f:
        total_content = f.read().strip()
    assert total_content == str(sum(usages)), (
        f"Expected dynamic total {sum(usages)}, got {total_content!r}"
    )
    with open(sentinel, "r") as f:
        assert f.read() == "UNCHANGED", "total_usage.txt was written in place instead of replaced"

    moved_total = False
    while True:
        try:
            data = os.read(inotify_fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset + 16 <= len(data):
            event_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            if event_wd == wd and (mask & IN_MOVED_TO) and name == "total_usage.txt":
                moved_total = True
    os.close(inotify_fd)
    os.unlink(sentinel)

    assert moved_total, "No atomic move into total_usage.txt was observed"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
